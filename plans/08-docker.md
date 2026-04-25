# 08 — Single Dockerfile + compose

## Goal

Build the entire 2.0 stack into one Docker image based on `perl:5.42-slim` (Debian-slim). `smoke.db` and the `data/reports/` tree live outside the container and are mounted in as a directory volume so data survives image rebuilds.

## Image strategy

Multi-stage build:

- **Stage 1 (`builder`)** — `perl:5.42-slim` + `build-essential` + sqlite/xz/ssl dev headers; install CPAN deps to `/build/local/` and vendor htmx.
- **Stage 2 (`runtime`)** — `perl:5.42-slim` with only the runtime libs; copy `local/` and app source; non-root user (uid 1000); expose 3000; run Hypnotoad in foreground.

(Decision #15 originally said Alpine, but DockerHub doesn't publish a `perl:5.42-alpine` image and apk's perl lags behind 5.42. Slim Debian gives us the same "lean and lockable" properties without compiling perl from source.)

## `Dockerfile`

```dockerfile
ARG PERL_VERSION=5.42

# ---------- builder ----------
FROM perl:${PERL_VERSION}-slim AS builder

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential libsqlite3-dev liblzma-dev libssl-dev zlib1g-dev \
        ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && cpan -T App::cpm

WORKDIR /build
COPY cpanfile cpanfile.snapshot ./
RUN cpm install --workers=4 --no-test --resolver=snapshot --resolver=metadb

# Vendor htmx so the runtime image has a real release rather than the placeholder.
RUN curl -fsSL https://unpkg.com/htmx.org@2.0.4/dist/htmx.min.js -o /build/htmx.min.js

# ---------- runtime ----------
FROM perl:${PERL_VERSION}-slim AS runtime

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        libsqlite3-0 liblzma5 libssl3 ca-certificates tini wget \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --uid 1000 smoke

COPY --from=builder /build/local       /app/local
COPY --from=builder /build/htmx.min.js /app/public/htmx.min.js
COPY --chown=smoke:smoke . /app

RUN mkdir -p /data && chown -R smoke:smoke /app /data

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
```

Notes:

- Listen port **3000** (decision #13). EXPOSE matches.
- `tini` is PID 1 so signals propagate cleanly. `/usr/bin/tini` is the Debian path.
- `--no-test` during dep build keeps the layer fast; CI runs the full test suite separately.
- Runtime image does **not** include `build-essential` or dev headers — keeps the image lean.
- `MOJO_MODE=production` selects `etc/coresmoke.production.conf` which sets `workers => 2` (decision #14).
- `TZ=UTC` (decision #27) — both for log timestamps and any DateTime defaults.
- `HEALTHCHECK` calls the `/healthz` endpoint (decision #34) so `docker ps` and orchestrators see liveness.

## Volume mount contract

The container reads/writes everything under `/data`. Mount the host's data directory:

```
host:  ./data/                  ↔  container: /data/
       ├── smoke.db                          ├── smoke.db
       ├── smoke.db-wal                      ├── smoke.db-wal
       ├── smoke.db-shm                      ├── smoke.db-shm
       └── reports/                          └── reports/
           └── ab/cd/ef/<hash>/                  └── ab/cd/ef/<hash>/
               ├── log_file.xz                       ├── log_file.xz
               └── ...                                └── ...
```

A directory mount keeps WAL sidecars and the per-report xz files together (decision #16). Mojo::SQLite creates and migrates `smoke.db` on first connect.

## `docker-compose.yml`

```yaml
services:
  smoke:
    build: .
    image: ghcr.io/${OWNER:-metacpan}/coresmoke:latest
    ports:
      - "3000:3000"
    volumes:
      - ./data:/data
    environment:
      MOJO_MODE: production
      SMOKE_DB_PATH: /data/smoke.db
      SMOKE_REPORTS_DIR: /data/reports
      TZ: UTC
    restart: unless-stopped
```

## `.dockerignore`

```
legacy/
local/
.git/
data/
log/
*.swp
plans/
README.md.bak
.github/
t/coverage/
```

`legacy/` and `plans/` are intentionally excluded — reference material, not runtime.

## Multi-arch build

CI uses `docker/setup-buildx-action` and `docker/build-push-action`:

```yaml
- uses: docker/build-push-action@v5
  with:
    platforms: linux/amd64,linux/arm64
    push: ${{ github.ref == 'refs/heads/main' }}
    tags: ghcr.io/${{ github.repository_owner }}/coresmoke:latest
```

Both `amd64` and `arm64` (decision #48). Push to `ghcr.io` (decision #46) with tag `:latest` only (decision #47). On PRs, build but don't push.

## Vulnerability scanning

After build, run Trivy on the image (decision #49), report-only:

```yaml
- uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'ghcr.io/${{ github.repository_owner }}/coresmoke:latest'
    format: 'table'
    exit-code: '0'    # never fail the build
    severity: 'HIGH,CRITICAL'
```

## Local dev workflow

```
docker compose build
docker compose up
# In another shell:
curl http://localhost:3000/system/ping
curl -H 'Content-Encoding: gzip' --data-binary @<(gzip < payload.json) \
     -H 'Content-Type: application/json' \
     -X POST http://localhost:3000/api/report
```

For development without Docker: `script/smoke morbo` (decision #43).

## Critical files to read

- `legacy/api/Dockerfile` (current Perl/Dancer container — for context)
- `legacy/web/Dockerfile` (Vue/Nginx — being retired)
- `legacy/api/environments/docker.yml` (env-specific config keys to preserve in `etc/coresmoke.production.conf`)

## Verification

1. `docker build -t coresmoke:test .` succeeds in under 10 minutes on a cold cache.
2. Image size is reasonable (< 300 MB target on slim Debian).
3. `docker run --rm coresmoke:test perl -V` reports 5.42.x.
4. `docker compose up` starts; `curl localhost:3000/system/ping` returns `pong`.
5. `docker inspect --format '{{.State.Health.Status}}' <container>` returns `healthy` after the start period.
6. After `docker compose down && docker compose up`, prior data persists (`./data/smoke.db` and `./data/reports/` survive).
7. Stop signal: `docker compose down` exits within ~2 seconds.
8. Container does not run as root: `docker exec <container> id` shows `uid=1000(smoke)`.
9. CI builds linux/amd64 and linux/arm64 images and pushes both manifests to `ghcr.io/.../coresmoke:latest` on main.
10. CI Trivy step uploads a report; build does not fail on findings.
