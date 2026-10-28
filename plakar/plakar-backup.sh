#!/usr/bin/env bash
# One Plakar backup of PLAKAR_SOURCE into the S3 store PLAKAR_STORE, then a check of the new snapshot.
#
# Required: PLAKAR_STORE (s3://<endpoint>/<bucket>/<prefix>), S3_ACCESS_KEY, S3_SECRET_KEY,
#           PLAKAR_PASSPHRASE (read by plakar itself), PLAKAR_SOURCE (e.g. postgres://user:password@host:5432/).
# Optional: HEARTBEAT_URL (called only on success), PLAKAR_SKIP_CHECK=1.
#
# The store must already exist (`plakar at <store> create`, done once by hand): a Job never creates one.
set -euo pipefail

for v in PLAKAR_STORE S3_ACCESS_KEY S3_SECRET_KEY PLAKAR_PASSPHRASE PLAKAR_SOURCE; do
    [ -n "${!v:-}" ] || { echo "missing $v" >&2; exit 2; }
done

plakar store add backup "$PLAKAR_STORE" \
    access_key="$S3_ACCESS_KEY" secret_access_key="$S3_SECRET_KEY" use_tls=true
plakar source add src "$PLAKAR_SOURCE"

log=$(mktemp)
plakar at @backup backup @src 2>&1 | tee "$log"
# A partial backup can still exit 0: only "completed without errors" counts as a success.
snapshot=$(sed -nE 's/^([0-9a-f]{8}): backup completed without errors.*/\1/p' "$log" | tail -1)
[ -n "$snapshot" ] || { echo "backup did not complete without errors" >&2; exit 1; }

if [ "${PLAKAR_SKIP_CHECK:-0}" != 1 ]; then
    plakar at @backup check "$snapshot"
fi

if [ -n "${HEARTBEAT_URL:-}" ]; then
    curl -fsS --max-time 30 --retry 3 "$HEARTBEAT_URL" > /dev/null
fi

echo "snapshot $snapshot OK"
