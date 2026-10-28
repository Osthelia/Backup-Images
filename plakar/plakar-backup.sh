#!/usr/bin/env bash
# Plakar backups of PLAKAR_SOURCE into the S3 store PLAKAR_STORE, then a check of each new snapshot.
#
# Required: PLAKAR_STORE (s3://<endpoint>/<bucket>/<prefix>), S3_ACCESS_KEY, S3_SECRET_KEY,
#           PLAKAR_PASSPHRASE (read by plakar itself), PLAKAR_SOURCE (e.g. postgres://user:password@host:5432/).
# PLAKAR_SOURCE may list several sources separated by spaces, each one `location` or `tag=location` (snapshot tag):
#           one snapshot per source; a failed source does not stop the others, but fails the run.
# Optional: PLAKAR_SOURCE_OPTIONS (`key=value ...` added to every source, e.g. its S3 credentials),
#           PLAKAR_CONCURRENCY (plakar -concurrency: Infomaniak answers 429 when a bucket is read too fast),
#           HEARTBEAT_URL (called only when every source succeeded), PLAKAR_SKIP_CHECK=1.
#
# The store must already exist (`plakar at <store> create`, done once by hand): a Job never creates one.
set -euo pipefail

for v in PLAKAR_STORE S3_ACCESS_KEY S3_SECRET_KEY PLAKAR_PASSPHRASE PLAKAR_SOURCE; do
    [ -n "${!v:-}" ] || { echo "missing $v" >&2; exit 2; }
done

plakar store add backup "$PLAKAR_STORE" \
    access_key="$S3_ACCESS_KEY" secret_access_key="$S3_SECRET_KEY" use_tls=true
read -ra options <<< "${PLAKAR_SOURCE_OPTIONS:-}"
concurrency=(${PLAKAR_CONCURRENCY:+-concurrency "$PLAKAR_CONCURRENCY"})

# One source: backup, then check. Returns non-zero on any failure.
backup() {
    local name=$1 location=$2 tag=$3 log snapshot
    plakar source add "$name" "$location" "${options[@]}" || return 1
    log=$(mktemp)
    plakar "${concurrency[@]}" at @backup backup ${tag:+-tag "$tag"} "@$name" 2>&1 | tee "$log" || return 1
    # A partial backup can still exit 0: only "completed without errors" counts as a success.
    snapshot=$(sed -nE 's/^([0-9a-f]{8}): backup completed without errors.*/\1/p' "$log" | tail -1)
    [ -n "$snapshot" ] || { echo "${tag:-source $name}: backup did not complete without errors" >&2; return 1; }
    if [ "${PLAKAR_SKIP_CHECK:-0}" != 1 ]; then
        plakar at @backup check "$snapshot" || return 1
    fi
    echo "snapshot $snapshot OK${tag:+ ($tag)}"
}

i=0 failed=0
for source in $PLAKAR_SOURCE; do
    tag=
    if [[ $source =~ ^([a-z0-9._-]+)=(.+)$ ]]; then
        tag=${BASH_REMATCH[1]} source=${BASH_REMATCH[2]}
    fi
    i=$((i + 1))
    backup "src$i" "$source" "$tag" || failed=1
done
[ "$failed" = 0 ] || exit 1

if [ -n "${HEARTBEAT_URL:-}" ]; then
    curl -fsS --max-time 30 --retry 3 "$HEARTBEAT_URL" > /dev/null
fi
