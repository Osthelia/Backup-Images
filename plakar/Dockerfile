# Plakar + integrations s3 and postgresql, with the Postgres 17 client tools (pg_dump, pg_dumpall, pg_restore, psql).
# The prebuilt integrations on plakar.io require a Plakar account: they are built from source here, which needs none.
FROM golang:1.26-bookworm AS build

ARG PLAKAR_VERSION=v1.1.7

ARG S3_VERSION=v1.1.10
ARG POSTGRESQL_VERSION=v1.1.2

ARG GO_UPGRADES="golang.org/x/net@latest golang.org/x/crypto@latest golang.org/x/text@latest golang.org/x/mod@latest google.golang.org/grpc@latest github.com/klauspost/compress@latest"

RUN apt-get update && apt-get install -y --no-install-recommends make git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth=1 --branch "${PLAKAR_VERSION}" https://github.com/PlakarKorp/plakar.git \
    && cd plakar && go get ${GO_UPGRADES} && go mod tidy \
    && CGO_ENABLED=0 go build -trimpath -o /out/plakar .

RUN git clone --depth=1 --filter=blob:none --sparse --branch "s3/${S3_VERSION}" \
        https://github.com/PlakarKorp/integrations.git s3 \
    && git clone --depth=1 --filter=blob:none --sparse --branch "postgresql/${POSTGRESQL_VERSION}" \
        https://github.com/PlakarKorp/integrations.git postgresql \
    && git -C s3 sparse-checkout set s3 && git -C postgresql sparse-checkout set postgresql \
    && mkdir -p /pkgs \
    && for p in "s3 ${S3_VERSION}" "postgresql ${POSTGRESQL_VERSION}"; do \
         set -- $p; \
         (cd "$1/$1" && go get ${GO_UPGRADES} && go mod tidy && make \
           && /out/plakar pkg create -out "/pkgs/$1_$2_linux_amd64.ptar" manifest.yaml "$2") || exit 1; \
       done

RUN mkdir -p /home/plakar \
    && for p in /pkgs/*.ptar; do HOME=/home/plakar /out/plakar pkg add -allow-unsigned "$p" > /dev/null; done

FROM debian:bookworm-slim

RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends ca-certificates curl postgresql-common \
    && /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y \
    && apt-get install -y --no-install-recommends postgresql-client-17 \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/ssl/private/ssl-cert-snakeoil.key /etc/ssl/certs/ssl-cert-snakeoil.pem

RUN useradd -u 10001 -m -s /bin/bash plakar

COPY --from=build /out/plakar /usr/local/bin/plakar
COPY --from=build --chown=10001:10001 /home/plakar/.local/share/plakar /home/plakar/.local/share/plakar
COPY --from=build --chown=10001:10001 /home/plakar/.cache/plakar/plugins /home/plakar/.cache/plakar/plugins
COPY --chmod=755 plakar-backup.sh /usr/local/bin/plakar-backup

USER plakar
WORKDIR /home/plakar

RUN plakar -disable-security-check && plakar pkg list

ENTRYPOINT ["/usr/local/bin/plakar-backup"]
