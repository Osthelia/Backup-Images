#!/usr/bin/env bash
# Retention for the Plakar stores: remove the snapshots older than PLAKAR_RETENTION, then `plakar maintenance`
# (two passes inside Plakar: packfiles no snapshot references are first coloured, then really deleted once
# PLAKAR_GRACEPERIOD, 7 d by default, has passed; so the space of a snapshot removed on day 30 is freed around day 37).
#
# Required: PLAKAR_STORES (space-separated s3://<endpoint>/<bucket>/<prefix>), S3_ACCESS_KEY, S3_SECRET_KEY (the key of the
#           cleanup role, the only one allowed to delete), PLAKAR_PASSPHRASE (read by plakar itself).
# Optional: PLAKAR_RETENTION (default 30d), PLAKAR_GRACEPERIOD (read by plakar maintenance),
#           PLAKAR_PRUNE_APPLY=1 (without it only prints what would be removed: a dry run),
#           HEARTBEAT_URL (called only when every store succeeded).
#
# Safety: a store is left untouched when it has no snapshot newer than the retention (backups stopped: removing the old
# ones would empty the store). Must not run while a backup runs (maintenance takes an exclusive lock on the store).
set -euo pipefail

for v in PLAKAR_STORES S3_ACCESS_KEY S3_SECRET_KEY PLAKAR_PASSPHRASE; do
    [ -n "${!v:-}" ] || { echo "missing $v" >&2; exit 2; }
done
retention=${PLAKAR_RETENTION:-30d}

# One store. Returns non-zero on any failure.
prune() {
    local location=$1 recent
    echo "== $location (retention $retention, apply=${PLAKAR_PRUNE_APPLY:-0})"
    plakar store add backup "$location" \
        access_key="$S3_ACCESS_KEY" secret_access_key="$S3_SECRET_KEY" use_tls=true || return 1

    recent=$(plakar at @backup ls -since "$retention" | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
    if [ "$recent" -eq 0 ]; then
        echo "$location: no snapshot newer than $retention, nothing removed" >&2
        return 1
    fi
    echo "$recent snapshot(s) newer than $retention are kept"

    if [ "${PLAKAR_PRUNE_APPLY:-0}" != 1 ]; then
        plakar at @backup rm -before "$retention" || return 1
        echo "dry run: PLAKAR_PRUNE_APPLY=1 to remove"
        return 0
    fi
    plakar at @backup rm -apply -before "$retention" || return 1
    plakar at @backup maintenance || return 1
    plakar at @backup check -latest || return 1
}

failed=0
for store in $PLAKAR_STORES; do
    prune "$store" || failed=1
    # `store add` fails on an existing name: drop it whatever the outcome.
    plakar store rm backup > /dev/null 2>&1 || true
done
[ "$failed" = 0 ] || exit 1

if [ -n "${HEARTBEAT_URL:-}" ]; then
    curl -fsS --max-time 30 --retry 3 "$HEARTBEAT_URL" > /dev/null
fi
