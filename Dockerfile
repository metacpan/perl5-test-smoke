#  =========================================================================
#  coresmoke (prod image)
#  -------------------------------------------------------------------------
#  Per-commit build. All apt and CPAN deps live in coresmoke-base (built
#  by .github/workflows/base.yml from Dockerfile.base whenever cpanfile or
#  cpanfile.snapshot change). This file just lays the source on top of
#  that base. A fresh build is essentially `COPY . /app` plus configuring
#  the entrypoint -- typically a few seconds.
#
#  Override BASE_IMAGE for local development:
#     docker build -f Dockerfile.base -t coresmoke-base:local .
#     docker build --build-arg BASE_IMAGE=coresmoke-base:local -t coresmoke:dev .
#  =========================================================================
ARG BASE_IMAGE=ghcr.io/metacpan/coresmoke-base:latest

FROM ${BASE_IMAGE}

# Layer the application source on top of the prebuilt base. The base has
# already created /app and /data, vendored htmx, installed CPAN deps into
# /app/local, and chowned everything to smoke:smoke. .dockerignore keeps
# public/htmx.min.js (the dev placeholder) out of the build context so
# this COPY does not overwrite the real vendored htmx from the base.
COPY --chown=smoke:smoke . /app

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
