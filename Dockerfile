#  =========================================================================
#  coresmoke (prod image)
#  -------------------------------------------------------------------------
#  Per-commit build. The heavy CPAN + apt install lives in coresmoke-base
#  (built by .github/workflows/base.yml from Dockerfile.base whenever
#  cpanfile or cpanfile.snapshot change). This file just lays the source
#  on top of that base, so a fresh build is essentially a `COPY .`.
#
#  Override BASE_IMAGE to build against a local base for development:
#     docker build -f Dockerfile.base -t coresmoke-base:local .
#     docker build --build-arg BASE_IMAGE=coresmoke-base:local -t coresmoke:dev .
#  =========================================================================
ARG PERL_VERSION=5.42
ARG BASE_IMAGE=ghcr.io/metacpan/coresmoke-base:latest

# Pull the prebuilt deps (perl + cpm + /build/local + /build/htmx.min.js).
FROM ${BASE_IMAGE} AS deps

# ---------- runtime ----------------------------------------------------------
FROM perl:${PERL_VERSION}-slim AS runtime

# Runtime deps only (no headers / build tools).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        libsqlite3-0 \
        liblzma5 \
        libssl3 \
        ca-certificates \
        tini \
        wget \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --uid 1000 smoke

# Copy installed CPAN deps and the vendored htmx from the base image.
COPY --from=deps /build/local         /app/local
COPY --from=deps /build/htmx.min.js   /app/public/htmx.min.js

# Copy the application source.
COPY --chown=smoke:smoke . /app

# Make sure the data directory exists and is owned by `smoke`.
RUN mkdir -p /data \
 && chown -R smoke:smoke /app /data

WORKDIR /app
USER smoke

ENV PERL5LIB=/app/local/lib/perl5:/app/lib \
    PATH=/app/local/bin:$PATH \
    SMOKE_DB_PATH=/data/smoke.db \
    SMOKE_REPORTS_DIR=/data/reports \
    MOJO_MODE=production \
    MOJO_HOME=/app \
    TZ=UTC

VOLUME ["/data"]
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://127.0.0.1:3000/healthz || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["script/smoke", "prefork", "--listen", "http://*:3000"]
