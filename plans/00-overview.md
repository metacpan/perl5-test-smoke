# 00 — Overview

## Why this rewrite

The current production stack is three separate repos (now mounted as submodules under `legacy/`):

- `legacy/sql` — PostgreSQL 14 schema dump with a `STORED GENERATED` `plevel` column populated by a custom PL/pgSQL function `git_describe_as_plevel()`.
- `legacy/api` — Dancer2 service exposing every method over **both JSONRPC 2.0 and REST** via `Dancer2::Plugin::RPC::*`, backed by `DBIx::Class` and the external `Perl5::CoreSmokeDB::Schema` distribution. Bread::Board IoC, Starman.
- `legacy/web` — Vue 3 SPA (Vite + Vuex + Axios), no Perl. Talks to the API over HTTP.

Operating three repos, two languages, two web stacks, and a heavy Postgres dependency for what is fundamentally a small app makes day-to-day maintenance hard. **2.0 collapses everything into one Perl/Mojolicious app on Perl 5.42.0, backed by SQLite, packaged as one Docker image.**

## Decisions (confirmed with user)

| Topic | Decision |
|------|----------|
| Frontend | Server-rendered Mojolicious EP templates. Vue SPA retired. |
| API protocol | REST + JSONRPC 2.0 parity — every legacy method exposed on both. |
| Data migration | Deferred. `smoke.db` starts empty. (See `10-deferred-migration.md`.) |
| Legacy ingest | Keep `POST /api/old_format_reports` for pre-1.81 Test::Smoke clients. |
| Database | SQLite, single file `smoke.db`, mounted into the container as a host volume. |
| Perl | 5.42.0; modern idioms (`use v5.42`, signatures, postfix deref, `class` where natural). |
| Container | Single multi-stage Dockerfile, `perl:5.42-slim` base, Hypnotoad on port 8080. |

## Repo layout

```
perl5-smoke/
├── legacy/                         # reference only — do not modify
│   ├── sql/  (Perl5-CoreSmokeDB)
│   ├── api/  (Perl5-CoreSmokeDB-API)
│   └── web/  (Perl5-CoreSmokeDB-Web)
├── lib/Perl5/CoreSmoke/            # new app code
│   ├── App.pm                      # Mojolicious base class
│   ├── Controller/{Api,JsonRpc,System,Ingest,Web}.pm
│   ├── Model/{DB,Reports,Search,Matrix,Plevel}.pm
│   └── Schema/migrations.sql
├── templates/                      # EP templates
├── public/                         # CSS, images, minimal JS
├── script/smoke                    # Mojo launcher
├── etc/coresmoke.conf              # Mojo config
├── t/                              # Test::Mojo suite
├── cpanfile
├── Dockerfile
├── docker-compose.yml              # local dev convenience
├── smoke.db                        # gitignored; mounted volume in prod
├── plans/                          # this directory
└── README.md
```

## Tech choices and rationale

- **Full Mojolicious app** (not Lite). Route surface is large and we want clean controller separation.
- **Mojo::SQLite** — built-in migrations, automatic `PRAGMA foreign_keys = ON`, WAL mode. Replaces Postgres + DBIx::Class + the external schema module.
- **In-app JSONRPC dispatcher**, not a CPAN plugin. The legacy app demonstrates the dispatch is small; sharing a single DAO between REST and JSONRPC keeps both protocols in sync.
- **Perl 5.42 `class` feature** for new value/service objects. Mojolicious controllers stay as `Mojolicious::Controller` subclasses since Mojo's own OO doesn't use `class`.
- **`Mojo::Log`** instead of Log4perl.
- **`Mojolicious::Plugin::Config`** with one config file per env.
- **`cpm`** instead of Carton for Docker dependency installation — faster and simpler.
- **Hypnotoad** instead of Starman.

## What is removed

- `Bread::Board` IoC, `Dancer2::Plugin::RPC::*`, `DBIx::Class`, the external `Perl5::CoreSmokeDB::Schema` module, `Carton`, `Starman`.
- The Vue SPA, Vuex, Vite, Vitest, Axios, the `legacy/web/Dockerfile`, the `legacy/web/private-config/docker-nginx.conf`. CSS and image assets are copied into `public/`.

## Backwards compatibility surface (must not break)

External clients (Test::Smoke installs, scrapers, the legacy SPA during cutover) hit these. Shapes must match the legacy responses exactly.

- `GET /api/latest`, `GET /api/searchparameters`, `GET|POST /api/searchresults`
- `GET /api/matrix`, `GET /api/submatrix`
- `GET /api/full_report_data/:rid`, `GET /api/report_data/:rid`
- `GET /api/logfile/:rid`, `GET /api/outfle/:rid`  (note legacy typo `outfle` is preserved)
- `GET /api/version`, `GET /api/reports_from_id/:rid`, `GET /api/reports_from_date/:epoch`
- `POST /api/report`, `POST /api/old_format_reports`
- `GET /system/ping|version|status|methods[/:plugin]`
- `POST /api` — JSONRPC 2.0 dispatch entry point, all of the above methods exposed by name
- `GET /api/openapi/web.{json,yaml}` — auto-generated from route metadata

`plevel` semantics (string sort key derived from `git_describe`) must match the legacy PL/pgSQL implementation byte-for-byte. See `02-database.md`.

## Sub-plan index

| # | File | Scope |
|---|------|-------|
| 00 | `00-overview.md` | This document. |
| 01 | `01-skeleton.md` | Mojolicious app skeleton. |
| 02 | `02-database.md` | SQLite schema, migrations, plevel port. |
| 03 | `03-api-rest.md` | REST controllers. |
| 04 | `04-api-jsonrpc.md` | JSONRPC 2.0 dispatcher. |
| 05 | `05-ingest.md` | `POST /api/report` + `old_format_reports`. |
| 06 | `06-business-logic.md` | Search filter, failure matrix, paging. |
| 07 | `07-web-templates.md` | Server-rendered pages replacing Vue SPA. |
| 08 | `08-docker.md` | Single Dockerfile + compose. |
| 09 | `09-testing.md` | Test::Mojo strategy, parity tests. |
| 10 | `10-deferred-migration.md` | Stub for importing legacy PG data. |

## Out of scope

- Importing legacy PostgreSQL data (~5.5M rows). Covered as a stub in plan 10.
- Authentication / ACLs — legacy is open; 2.0 stays open.
- Kubernetes manifests — we ship a Dockerfile only and let ops wrap it.
