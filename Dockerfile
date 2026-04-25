ARG PERL_VERSION=5.42

# ---------- builder ----------------------------------------------------------
FROM perl:${PERL_VERSION}-slim AS builder

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential \
        libsqlite3-dev \
        liblzma-dev \
        libssl-dev \
        zlib1g-dev \
        ca-certificates \
        curl \
 && rm -rf /var/lib/apt/lists/* \
 && cpan -T App::cpm

WORKDIR /build

# Snapshot-pinned install for reproducibility (decision #20).
COPY cpanfile cpanfile.snapshot ./
RUN cpm install --workers=4 --no-test --resolver=snapshot --resolver=metadb --show-build-log-on-failure

# Vendor htmx -- decision #17. Pinned to a stable major release.
RUN curl -fsSL https://unpkg.com/htmx.org@2.0.4/dist/htmx.min.js \
        -o /build/htmx.min.js

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

# Copy installed deps and the vendored htmx into the runtime image.
COPY --from=builder /build/local         /app/local
COPY --from=builder /build/htmx.min.js   /app/public/htmx.min.js

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
