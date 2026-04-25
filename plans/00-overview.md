# 00 — Overview

## Why this rewrite

The current production stack is three separate repos (now mounted as submodules under `legacy/`):

- `legacy/sql` — PostgreSQL 14 schema dump with a `STORED GENERATED` `plevel` column populated by a custom PL/pgSQL function `git_describe_as_plevel()`.
- `legacy/api` — Dancer2 service exposing every method over **both JSONRPC 2.0 and REST** via `Dancer2::Plugin::RPC::*`, backed by `DBIx::Class` and the external `Perl5::CoreSmokeDB::Schema` distribution. Bread::Board IoC, Starman.
- `legacy/web` — Vue 3 SPA (Vite + Vuex + Axios), no Perl. Talks to the API over HTTP.

Operating three repos, two languages, two web stacks, and a heavy Postgres dependency for what is fundamentally a small app makes day-to-day maintenance hard. **2.0 collapses everything into one Perl/Mojolicious app on Perl 5.42.0, backed by SQLite, packaged as one Docker image.**

## Decisions (confirmed with user across three Q&A rounds)

| Topic | Decision |
|------|----------|
| Module namespace | `CoreSmoke` (drop `Perl5::` prefix) |
| App display name | "Perl 5 Core Smoke DB" |
| Version | 2.0 |
| License | Same terms as Perl itself |
| Frontend | Server-rendered Mojolicious EP templates + HTMX |
| API protocol | REST + JSONRPC 2.0 parity (built together, one DAO) |
| `/api/outfle` typo | Dropped — only `/api/outfile/:rid` is exposed |
| Pre-1.81 ingest | Keep `POST /api/old_format_reports` + built-in `POST /report` alias |
| CORS | Wildcard `*`, configurable |
| `dbversion` | Bumped to `4` |
| Database | SQLite at `/data/smoke.db` (host volume) |
| Journal mode | WAL; mount the data directory at `/data` |
| FK enforcement | `ON DELETE CASCADE` on `config`, `result`, `failures_for_env` |
| **Report files** | **All five legacy bytea columns dropped from DB; written to disk under `/data/reports/<sharded-hash>/<field>.xz`** |
| At-rest compression | xz, all files |
| Atomicity | Best-effort: write files first, INSERT row second |
| Request gzip | Honor `Content-Encoding: gzip` on `POST /api/report` |
| Max request body | 16 MB |
| Time zone | UTC everywhere (DB ISO 8601 UTC, container `TZ=UTC`) |
| Default page size | 25 |
| Pagination | HTMX infinite scroll on `/latest` and `/search` |
| Theme | Light only |
| RSS/Atom | None |
| Health endpoints | `GET /healthz` and `GET /readyz` |
| Logging | Mojo::Log to STDERR |
| Container base | `perl:5.42-slim` (Debian-slim) |
| Listen port | 3000 |
| Hypnotoad workers | 2 |
| Container user | non-root, fixed UID 1000 |
| Multi-arch builds | linux/amd64 + linux/arm64 |
| Container registry | `ghcr.io/<owner>/coresmoke:latest` |
| Vulnerability scan | Trivy in CI, report-only |
| CI | GitHub Actions (test job + docker build + Trivy + perlcritic + coverage) |
| perlcritic | Severity 5, fail the build |
| Coverage | Devel::Cover, report only (no threshold) |
| Test DB | Single shared `t/test.db`, reset between tests; tests run sequentially |
| Hot reload | `morbo` for development |
| Plevel parity corpus | Hand-curated ~30 representative `git_describe` strings |
| `cpanfile.snapshot` | Committed |
| Legacy submodules | Kept indefinitely as reference |
| Backups | Out of scope; S3 planned but later |
| Metrics | Out of scope |
| Retention | None — keep everything forever |
| Data migration | Deferred (`10-deferred-migration.md`) |

## Repo layout

```
perl5-smoke/
├── legacy/                         # reference only — do not modify
│   ├── sql/  (Perl5-CoreSmokeDB)
│   ├── api/  (Perl5-CoreSmokeDB-API)
│   └── web/  (Perl5-CoreSmokeDB-Web)
├── lib/CoreSmoke/                  # new app code
│   ├── App.pm                      # Mojolicious base class
│   ├── Controller/{Api,JsonRpc,System,Ingest,Web}.pm
│   ├── JsonRpc/Methods.pm          # shared method registry
│   ├── Model/{DB,Reports,Search,Matrix,Plevel,ReportFiles,Ingest}.pm
│   └── Schema/migrations.sql
├── templates/                      # EP templates
├── public/                         # CSS, htmx.min.js, images
├── script/smoke                    # Mojo launcher
├── etc/
│   ├── coresmoke.conf              # default Mojo config
│   ├── coresmoke.development.conf
│   ├── coresmoke.test.conf
│   ├── coresmoke.production.conf
│   └── openapi.yaml                # hand-authored OpenAPI spec
├── t/                              # Test::Mojo suite
│   ├── data/                       # JSON fixtures + plevel-corpus.tsv
│   └── lib/TestApp.pm              # shared t/test.db + reset_db helper
├── data/                           # gitignored: smoke.db, smoke.db-wal, smoke.db-shm, reports/
├── cpanfile
├── cpanfile.snapshot
├── Dockerfile                      # multi-stage on perl:5.42-slim
├── docker-compose.yml
├── .perlcriticrc
├── .github/workflows/ci.yml
├── plans/                          # this directory
└── README.md
```

## Tech choices and rationale

- **Full Mojolicious app** (not Lite). Route surface is large; controller separation pays off.
- **Mojo::SQLite** — built-in migrations, automatic `PRAGMA foreign_keys = ON`, WAL by default.
- **In-app JSONRPC dispatcher** in `Controller::JsonRpc`. Shares the registry in `JsonRpc/Methods.pm` with REST controllers — single source of truth, no CPAN plugin.
- **Perl 5.42 `class` feature** for new value/service objects. Mojolicious controllers stay as `Mojolicious::Controller` subclasses.
- **HTMX** for filter forms, matrix drill-down, and infinite scroll. ~14 KB, vendored at `public/htmx.min.js`.
- **xz** for on-disk report files. `IO::Compress::Xz` / `IO::Uncompress::UnXz` for I/O.
- **`Mojo::Log`** to STDERR.
- **`Mojolicious::Plugin::Config`** with one config file per `MOJO_MODE`.
- **`cpm`** for dep installation (Carton retired).
- **Hypnotoad** in `prefork` mode (Starman retired). Port 3000, 2 workers.

## What is removed

- `Bread::Board` IoC, `Dancer2::Plugin::RPC::*`, `DBIx::Class`, the external `Perl5::CoreSmokeDB::Schema` module, `Carton`, `Starman`.
- The Vue SPA, Vuex, Vite, Vitest, Axios, the `legacy/web/Dockerfile`, the `legacy/web/private-config/docker-nginx.conf`. The legacy CSS is **not** copied — 2.0 restyles from scratch.
- The five bytea columns on `report` (now files on disk) and the `/api/outfle` typo route.

## Backwards compatibility surface (must not break)

External clients (Test::Smoke installs, scrapers) hit these. Shapes must match the legacy responses.

- `GET /api/latest`, `GET /api/searchparameters`, `GET|POST /api/searchresults`
- `GET /api/matrix`, `GET /api/submatrix`
- `GET /api/full_report_data/:rid`, `GET /api/report_data/:rid`
- `GET /api/logfile/:rid`, **`GET /api/outfile/:rid`** (corrected from legacy `outfle`)
- `GET /api/version`, `GET /api/reports_from_id/:rid`, `GET /api/reports_from_date/:epoch`
- `POST /api/report`, `POST /api/old_format_reports`, **`POST /report`** (built-in alias)
- `GET /system/ping|version|status|methods[/:plugin]`
- `POST /api` — JSONRPC 2.0 dispatch entry point, every method exposed by name
- `GET /api/openapi/web.{json,yaml}`
- `GET /healthz`, `GET /readyz` (new in 2.0)

`plevel` semantics (string sort key derived from `git_describe`) must match the legacy PL/pgSQL function for our hand-curated parity corpus. See `02-database.md`.

## Sub-plan index

| # | File | Scope |
|---|------|-------|
| 00 | `00-overview.md` | This document. |
| 01 | `01-skeleton.md` | Mojolicious app skeleton. |
| 02 | `02-database.md` | SQLite schema (no BLOBs, `report_hash` column), migrations, plevel port. |
| 03 | `03-api-rest.md` | REST controllers. |
| 04 | `04-api-jsonrpc.md` | JSONRPC 2.0 dispatcher (built alongside REST). |
| 05 | `05-ingest.md` | `POST /api/report` + `old_format_reports` + `/report` alias; gzip request, xz-on-disk files. |
| 06 | `06-business-logic.md` | Search filter, failure matrix, `Model::ReportFiles` for on-disk file I/O. |
| 07 | `07-web-templates.md` | Server-rendered EP pages with HTMX + infinite scroll, restyled CSS. |
| 08 | `08-docker.md` | Multi-stage Dockerfile on perl:5.42-slim + compose; multi-arch + ghcr.io + Trivy. |
| 09 | `09-testing.md` | Test::Mojo strategy, REST/JSONRPC parity, perlcritic, Devel::Cover. |
| 10 | `10-deferred-migration.md` | Stub for importing legacy PG data + files. |

## Out of scope

- Importing legacy PostgreSQL data and report files (~5.5M rows). Covered as a stub in plan 10.
- Authentication / ACLs — legacy is open; 2.0 stays open.
- Kubernetes manifests — we ship a Dockerfile only.
- Backups — S3-based backups are planned but not in 2.0; documented in README.
- Metrics / tracing — defer.
- Retention / cleanup — no built-in policy.
