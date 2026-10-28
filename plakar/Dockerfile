# Plakar + integrations s3 and postgresql, with the Postgres 17 client tools (pg_dump, pg_dumpall, pg_restore, psql).
# The prebuilt integrations on plakar.io require a Plakar account: they are built from source here, which needs none.
FROM golang:1.26-bookworm AS build

ARG PLAKAR_VERSION=v1.1.7

RUN apt-get update && apt-get install -y --no-install-recommends make git \
    && rm -rf /var/lib/apt/lists/*

RUN go install github.com/PlakarKorp/plakar@${PLAKAR_VERSION}

# `pkg build` takes the latest release of each integration (s3 v1.1.10 and postgresql v1.1.2 on 2026-10-28).
WORKDIR /pkgs
RUN plakar pkg build s3 && plakar pkg build postgresql

FROM postgres:17-bookworm

# ca-certificates: without them, TLS to the S3 endpoint fails (x509: certificate signed by unknown authority).
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -u 10001 -m -s /bin/bash plakar

COPY --from=build /go/bin/plakar /usr/local/bin/plakar
COPY --from=build /pkgs/*.ptar /opt/plakar/
COPY plakar-backup.sh /usr/local/bin/plakar-backup

USER plakar
WORKDIR /home/plakar

# Integrations are installed in ~/.cache/plakar/plugins at build time, so each run starts immediately.
# The security check queries the releases feed on every run: the image is updated through this repository instead.
RUN plakar -disable-security-check \
    && for p in /opt/plakar/*.ptar; do plakar pkg add -allow-unsigned "$p" > /dev/null; done \
    && plakar pkg list

ENTRYPOINT ["/usr/local/bin/plakar-backup"]
