# Backup-Images

Images used by the off-site backups of the Osthelia cluster (CronJobs in Osthelia/GitOps).

## `plakar/` → `ghcr.io/osthelia/plakar`

Plakar (version in `ARG PLAKAR_VERSION`) with its `s3` and `postgresql` integrations built from source (the prebuilt ones
require a Plakar account), on top of `postgres:17-bookworm` for `pg_dump` / `pg_dumpall` / `pg_restore` / `psql`.
Runs as uid 10001. Entry point: `plakar-backup` (see the header of `plakar/plakar-backup.sh` for its variables).

Tags pushed by `.github/workflows/plakar.yml` on every change under `plakar/`: full commit SHA (deployed by GitOps),
Plakar version, `latest`.

The Postgres major version of the image must match the cluster's (`pg_dump` refuses a newer server).

### Restore (Postgres)

```bash
plakar store add backup s3://sos-ch-dk-2.exo.io/osthelia-backup/postgres access_key=… secret_access_key=… use_tls=true
plakar at @backup ls                                   # snapshots
plakar at @backup ls <snapshot>:/                      # 00000-globals.sql + one <n>-<db>.dump per database
plakar destination add dst "postgres://user:password@host:5432/" recreate=true
plakar at @backup restore -to @dst <snapshot>
```

Without `recreate=true` the restore fails when the database does not exist yet.
