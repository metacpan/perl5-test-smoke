# 08 — Single Dockerfile + compose

## Goal

Build the entire 2.0 stack (API + web + ingest) into one Docker image. `smoke.db` lives outside the container and is mounted in as a volume so data survives image rebuilds.

## Image strategy

Multi-stage build on `perl:5.42-slim` (Debian-slim):

- **Stage 1 (`builder`)**: install build toolchain + `cpm`, copy `cpanfile`, install deps to `/build/local/`.
- **Stage 2 (`runtime`)**: copy `local/`, copy app source, install only runtime libs (libsqlite3, libssl3), drop into a non-root user, expose 8080, run Hypnotoad.

## `Dockerfile`

```dockerfile
ARG PERL_VERSION=5.42

FROM perl:${PERL_VERSION}-slim AS builder

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential \
        libsqlite3-dev \
        libssl-dev \
        zlib1g-dev \
        ca-certificates \
        curl \
 && rm -rf /var/lib/apt/lists/*

RUN cpan -T App::cpm

WORKDIR /build
COPY cpanfile cpanfile.snapshot* ./
RUN cpm install --workers=4 --no-test --resolver=metadb --show-build-log-on-failure


FROM perl:${PERL_VERSION}-slim AS runtime

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        libsqlite3-0 \
        libssl3 \
        ca-certificates \
        tini \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --uid 1000 smoke

COPY --from=builder /build/local /app/local
COPY --chown=smoke:smoke . /app

WORKDIR /app
USER smoke

ENV PERL5LIB=/app/local/lib/perl5:/app/lib \
    PATH=/app/local/bin:$PATH \
    SMOKE_DB_PATH=/data/smoke.db \
    MOJO_MODE=production \
    MOJO_HOME=/app

VOLUME ["/data"]
EXPOSE 8080

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["script/smoke", "prefork", "--listen", "http://*:8080"]
```

Notes:

- `tini` is PID 1 so signals propagate cleanly.
- `--no-test` during dep build keeps the layer fast; CI runs the test suite separately against the same `local/`.
- The runtime image does **not** include `build-essential` or headers — keeps the image slim.
- Hypnotoad in foreground via `prefork` is fine; we don't want the daemonized form inside a container.
- `MOJO_MODE=production` selects `etc/coresmoke.production.conf` if present.

## Volume mount contract

The container reads/writes `smoke.db` at `/data/smoke.db`. The host directory `./` is mounted to `/data`, so:

```
host:  ./smoke.db          ↔  container: /data/smoke.db
host:  ./smoke.db-wal      ↔  container: /data/smoke.db-wal
host:  ./smoke.db-shm      ↔  container: /data/smoke.db-shm
```

WAL and shared-memory files appear next to `smoke.db` because Mojo::SQLite enables WAL by default. They must be on the same filesystem as the DB file.

The host `smoke.db` file does not need to exist before the first run; Mojo::SQLite creates and migrates it on first connect.

## `docker-compose.yml`

```yaml
services:
  smoke:
    build: .
    image: coresmoke:latest
    ports:
      - "8080:8080"
    volumes:
      - ./smoke.db:/data/smoke.db
      - ./smoke.db-wal:/data/smoke.db-wal
      - ./smoke.db-shm:/data/smoke.db-shm
    environment:
      MOJO_MODE: production
      SMOKE_DB_PATH: /data/smoke.db
    restart: unless-stopped
```

Bind-mounting the three SQLite files individually (rather than a directory) avoids the SPA-style "mount over /data" trap on macOS where the host directory permissions clash with the container user. If the user prefers a directory mount, switch to `- ./db:/data` and adjust `SMOKE_DB_PATH=/data/smoke.db`.

## `.dockerignore`

```
legacy/
local/
.git/
log/
*.swp
plans/
t/data/*.large
README.md.bak
```

`legacy/` is intentionally excluded from the image — it's reference material only.

## Local dev workflow

```
docker compose build
docker compose up
# In another shell:
curl http://localhost:8080/system/ping
curl -X POST http://localhost:8080/api/report \
     -H 'Content-Type: application/json' \
     -d "{\"report_data\": $(cat legacy/api/t/data/idefix-gff5bbe677.jsn)}"
```

## Critical files to read

- `legacy/api/Dockerfile` (current Perl/Dancer container — for context, not as a template)
- `legacy/web/Dockerfile` (Vue/Nginx container — being retired)
- `legacy/api/environments/docker.yml` (env-specific config keys to preserve in `etc/coresmoke.production.conf`)

## Verification

1. `docker build -t coresmoke:test .` succeeds in under 5 minutes on a cold cache.
2. Image size is < 300 MB (for sanity; not a hard limit).
3. `docker run --rm coresmoke:test perl -V` reports 5.42.x.
4. `docker compose up` starts; `curl localhost:8080/system/ping` returns `pong`.
5. After `docker compose down && docker compose up`, prior data persists (`smoke.db` survives container recreation).
6. Stop signal: `docker compose down` exits within ~2 seconds (tini + Hypnotoad graceful shutdown).
7. `docker run --rm -u 0:0 coresmoke:test id` shows the container does **not** start as root by default (it should refuse — the image specifies `USER smoke`).
