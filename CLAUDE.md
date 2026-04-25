# CLAUDE.md — project-specific notes for AI assistants

This is a Mojolicious 2.0 rewrite of the legacy CoreSmokeDB stack. It
collapses three repos (`Perl5-CoreSmokeDB{,-API,-Web}`, mounted under
`legacy/`) into one Perl 5.42 app backed by SQLite, with on-disk xz
report files instead of `bytea` columns. The `plans/` directory holds
the planning docs; this file is the **gotchas and conventions** layer
on top.

## Where things live

```
lib/CoreSmoke/         — namespace is `CoreSmoke`, NOT `Perl5::CoreSmoke`
  App.pm               — Mojolicious base class
  Controller/          — Api, JsonRpc, System, Ingest, Web
  JsonRpc/Methods.pm   — single registry shared by REST + JSONRPC
  Model/               — DB, Reports, Search, Matrix, Plevel,
                         ReportFiles, Ingest
  Schema/migrations.sql
templates/             — Mojolicious EP templates
public/                — CSS + (gitignored) htmx.min.js
script/{smoke,migrate,fix-plevels,import-from-pgdump}
etc/{coresmoke,*.conf,openapi.yaml}
data/                  — gitignored: SQLite + reports/ tree
t/                     — sequential prove (single shared t/test.db)
plans/00..10/          — the planning docs
```

## DB / file locations by mode

| Mode | DB path | Reports tree |
|------|---------|--------------|
| development (`make start`/`make dev`) | `data/development.db` | `data/reports/` |
| test (TestApp.pm sets MOJO_MODE=test) | `t/test.db` | `t/data/reports-tmp/` |
| production (Docker container) | `/data/smoke.db` (env-mounted volume) | `/data/reports/` |

`Model::DB` and `Model::ReportFiles` resolve relative paths under
`MOJO_HOME` via `_resolve_path`; absolute paths from `$ENV{SMOKE_DB_PATH}`
or `$ENV{SMOKE_REPORTS_DIR}` pass through unchanged.

## Auto-migrate is OFF in development

`auto_migrate => 0` in `etc/coresmoke.development.conf`. `make start`
refuses to silently fabricate an empty DB. Run **one of**:

- `make migrate` — empty schema only
- `make dev-db SRC=csdb.psql` — populated from a pg_dump
- `make fix-plevels` — recompute `report.plevel` after a Plevel.pm change

Production and test modes still auto-migrate (container's first boot
needs to bootstrap an empty `/data`; tests reset `t/test.db` between
runs).

## Things that bit us once and shouldn't again

### `return` vs `return undef`

`map { decode_copy_field($_) } @raw` calls the sub in **list context**.
Bare `return;` there yields the empty list `()`, NOT `(undef)`. A
single bug like that ate every `\N` (NULL) field in the pg-dump
importer and shifted every subsequent column in the row.

**Rule**: in any sub that may be called in list context and represents
a "this slot is null but should still be counted" semantic, use
`return undef;` with a `## no critic (Subroutines::ProhibitExplicitReturnUndef)`
exemption + a one-line comment. Plain early returns elsewhere stay
`return;`.

### `use v5.42` enables strict ASCII source encoding

Em-dashes (`—`) in comments will break compilation. Stick to ASCII in
.pm files.

`Date::Parse` uses `eval "..."` with non-ASCII month names, which dies
under v5.42's strict ASCII. Files that import it need:

```perl
use v5.42;
no source::encoding;   # Date::Parse uses eval-strings w/ non-ASCII chars
```

(Currently `lib/CoreSmoke/Model/Ingest.pm`.)

### Mojolicious EP templates: `print` doesn't go to the output

```ep
% if ($x) { print 'selected'; }   # WRONG — writes to controller stdout
<%= $x ? 'selected' : '' %>       # right
<%= selected_if($x) %>            # right (helper in App.pm)
```

The latent `print 'selected'` bug meant our `<select>` dropdowns
weren't actually marking the picked option `selected` — only became
visible after we started swapping the form on filter change.

### Mojolicious helpers we register

App.pm registers a few helpers that aren't in `Mojolicious::Plugin::DefaultHelpers`:

- `url_escape($s)` — wraps `Mojo::Util::url_escape`. Default Mojo
  doesn't expose it, but our templates use it for query-string
  assembly.
- `selected_if($cond)` — returns `'selected'` or `''` for
  `<option>`/`<input>` markup.
- `sqlite`, `report_files`, `reports`, `ingest` — DAO accessors.

### Controller namespace

```perl
$self->routes->namespaces(['CoreSmoke::Controller']);
```

Without this, Mojolicious looks for controllers under
`CoreSmoke::App::Controller::*` and 500s with "Controller does not exist".

### Mojo::SQLite pragmas

Mojo::SQLite does **not** enable `PRAGMA foreign_keys = ON` or
`journal_mode = WAL` by default. `Model::DB::sqlite()` registers an
`on(connection => ...)` callback that runs both for every new handle.

### `or die` in hash construction

`path => $args{path} or die '...'` parses as
`(path, $args{path}) or die '...'` — the right-hand `or` consumes the
pair. Use `//`:

```perl
my $path = $args{path} // die 'path required';
my $self = bless { path => $path, ... }, $class;
```

### Hypnotoad doesn't preserve cwd

Hence `_resolve_path` in App.pm. Also the `Mojolicious::Plugin::Config`
`pid_file` is resolved against `cwd` not `MOJO_HOME`, so we rewrite it
in startup too.

### HTMX recipes that work here

- **Replace the trigger element on infinite scroll**: `hx-swap="outerHTML"`
  (not `afterend`, which leaves stale "Loading more..." rows).
- **Refresh form + table together on filter change**: target a wrapper
  `<div id="search-region">` with `hx-swap="outerHTML"`. Distinguish
  form-change requests from infinite-scroll requests via the
  `HX-Trigger` header (form has id="search-form", load-more `<tr>` has
  no id).
- **Live-update a header during infinite scroll**: emit an OOB
  `<element id="..." hx-swap-oob="true">` from the same response. Gate
  via a stash flag so the OOB markup only appears on HTMX responses,
  not on the initial full-page render (where it would just duplicate
  the inline element).
- **Push a clean URL**: `hx-push-url="true"` + `hx-on::config-request`
  to drop default-valued (`all`/empty) params from
  `event.detail.parameters` before HTMX builds the URL.

### SQLite GLOB vs LIKE

LIKE is case-insensitive for ASCII; GLOB is case-sensitive. The
Status filter on `/search` matches `FAIL(M)` ≠ `FAIL(m)` via GLOB
patterns like `FAIL(*M*)`.

### Docker

- Two-image build:
  - `Dockerfile.base` (built by `.github/workflows/base.yml`) carries
    apt + CPAN deps + the unprivileged `smoke` user + vendored htmx.
    Rebuilds **only** when `cpanfile`, `cpanfile.snapshot`, or
    `Dockerfile.base` change (or weekly cron, or workflow_dispatch).
    `no-cache: true` so the install really runs each time.
  - `Dockerfile` is just `FROM ${BASE_IMAGE} + COPY . /app + ENV/CMD`.
    Per-commit builds are essentially a single COPY layer.
- Base image is `perl:5.42-slim` (Debian-slim). `perl:5.42-alpine`
  isn't published, so don't try to switch to Alpine.
- `COPY --chown=smoke:smoke` instead of `chown -R` after COPY: avoids
  duplicating the entire CPAN tree into a new layer.
- The CI docker job is gated `if: github.event_name == 'push' &&
  github.ref == 'refs/heads/main'` — PRs run only the test job.

### CI gotchas

- `perl-actions/install-with-cpm@v2` defaults `global: true` and
  `sudo: true`. We use `sudo: false` (slim has no sudo, and we run as
  root in the container anyway) and `snapshot: false` (action calls
  Carton::Snapshot which isn't installed yet at that point).
- `cpm --workers=6` (1.5× the 4-vCPU runner) keeps cores busy during
  network/disk waits.
- Capture cpm output to a log and dump on failure only — Menlo's
  per-file install lines drown the build log otherwise.

## Conventions

- **Tests are sequential**: single shared `t/test.db` reset between
  tests. `prove -lr t/`, no `-j`.
- **perlcritic severity 5**, fail on violation. Run via `make critic`.
- **Devel::Cover** report-only in CI, no threshold.
- **Commits**: detailed body explaining the why; ends with
  `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- **Backwards-compat URLs**: `POST /report` (alias for
  `old_format_reports`), `POST /api/old_format_reports`,
  `gzip` Content-Encoding accepted on `POST /api/report`. Legacy
  `/api/outfle` (typo) was deliberately dropped — only
  `/api/outfile/:rid` is exposed.
- **`legacy/` is reference only**: never modify. Submodules in
  `.gitmodules` use **relative paths and https://** URLs (the original
  `git submodule add` with absolute paths broke `git submodule status`).

## Common operations

```sh
make start                     # hypnotoad on :3000 (dev mode)
make stop / make reload
make dev                       # morbo with auto-reload

make migrate                   # empty schema in data/development.db
make dev-db SRC=csdb.psql      # populate from pg_dump
make fix-plevels               # recompute report.plevel for every row

make test                      # prove -lr t/  (sequential)
make critic                    # perlcritic --severity 5 lib/ script/
make cover                     # Devel::Cover report

make build                     # brew + cpan + vendored htmx
make vendor                    # just fetch public/htmx.min.js

# Docker (prod)
docker compose up              # ./data:/data, port 3000
```

## Plans

`plans/00-overview.md` is the master index. Plans 01–10 cover
skeleton, schema, REST, JSONRPC, ingest, business logic, web
templates, Docker, testing, and the deferred legacy-data migration.
The 49 confirmed decisions live at the top of the master plan in
`/Users/toddr/.claude/plans/using-the-3-repos-typed-raven.md` (private
to the developer's claude data dir, not in the repo).
