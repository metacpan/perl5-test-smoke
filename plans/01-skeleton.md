# 01 — App skeleton

## Goal

Stand up an empty but bootable Mojolicious app on Perl 5.42.0 in the repo root with the directory structure, config plumbing, and dependency manifest the rest of the work plugs into.

## Files to create

### `cpanfile`

```perl
requires 'perl', '5.042000';

# core framework
requires 'Mojolicious',           '>= 9.34';
requires 'Mojo::SQLite',          '>= 3.009';

# config
requires 'Mojolicious::Plugin::Config';

# misc
requires 'JSON::PP',              '>= 4.16';
requires 'Digest::MD5';
requires 'Date::Parse';
requires 'DateTime';
requires 'DateTime::Format::SQLite';

# request gzip + on-disk xz files
requires 'IO::Compress::Gzip';
requires 'IO::Uncompress::Gunzip';
requires 'IO::Compress::Xz';
requires 'IO::Uncompress::UnXz';

on 'develop' => sub {
    requires 'Test::More',        '>= 1.302';
    requires 'Test::Mojo';
    requires 'Test::Deep';
    requires 'Test::Warnings';
    requires 'Perl::Critic';
    requires 'Devel::Cover';
};
```

`cpanfile.snapshot` is committed (decision #20) for reproducible builds. Generate with `cpm install -L local/ && cpm dump --to-snapshot`.

### `script/smoke`

Mojolicious launcher: `#!/usr/bin/env perl`, `use FindBin; use lib "$FindBin::Bin/../lib"; use lib "$FindBin::Bin/../local/lib/perl5"; use Mojolicious::Commands; Mojolicious::Commands->start_app('CoreSmoke::App')`. Mark executable.

### `lib/CoreSmoke/App.pm`

`Mojolicious` subclass. In `startup`:

1. Load config via `$self->plugin('Config' => { file => $self->_config_file })`. Resolve config file from `MOJO_CONFIG` or `etc/coresmoke.conf` relative to `$self->home`. Per-`MOJO_MODE` overrides via `etc/coresmoke.<mode>.conf`.
2. Resolve the SQLite path: `$ENV{SMOKE_DB_PATH} // $self->config->{db_path} // $self->home->child('data/smoke.db')`.
3. Resolve the report files root: `$ENV{SMOKE_REPORTS_DIR} // $self->config->{reports_dir} // $self->home->child('data/reports')`.
4. Register a `sqlite` helper that returns a memoized `Mojo::SQLite` configured with the migrations file at `lib/CoreSmoke/Schema/migrations.sql`.
5. `$self->sqlite->migrations->migrate` on startup so a freshly mounted empty `smoke.db` self-initializes.
6. Register helpers: `reports`, `ingest`, `report_files` (each constructs a memoized service object).
7. Register a `before_dispatch` hook that gunzips request bodies whose `Content-Encoding: gzip` header is set (for `POST /api/report`).
8. Register an `after_dispatch` hook that adds the CORS header from `cors_allow_origin` config (default `*`).
9. Mount routes:
   - `$r->get('/healthz')->to('System#healthz')`
   - `$r->get('/readyz')->to('System#readyz')`
   - `/system/*` REST routes
   - `/api/*` REST routes (controller stubs filled by plans 03/05)
   - `$r->any([qw(POST)] => '/api')->to('JsonRpc#dispatch')`
   - `$r->any([qw(POST)] => '/system')->to('JsonRpc#dispatch')`
   - `$r->post('/report')->to('Ingest#post_old_format_report')` (legacy alias)
   - Web routes: `/`, `/latest`, `/search`, `/matrix`, `/submatrix`, `/about`, `/report/:rid`, `/file/log_file/:rid`, `/file/out_file/:rid`
10. `max_request_size = 16 * 1024 * 1024` (16 MB, decision #29).
11. Set `$self->log->level($self->config->{log_level} // 'info')`. Mojo::Log defaults to STDERR (decision #23).

Use `use v5.42; use experimental qw(signatures);` at the top.

### `etc/coresmoke.conf` (default)

```perl
{
    db_path           => $ENV{SMOKE_DB_PATH}      // 'data/smoke.db',
    reports_dir       => $ENV{SMOKE_REPORTS_DIR}  // 'data/reports',
    log_level         => $ENV{SMOKE_LOG_LEVEL}    // 'info',
    cors_allow_origin => '*',
    app_name          => 'Perl 5 Core Smoke DB',
    app_version       => '2.0',
    hypnotoad => {
        listen           => ['http://*:3000'],
        workers          => 2,
        clients          => 100,
        accepts          => 100,
        graceful_timeout => 30,
        proxy            => 1,
    },
};
```

`etc/coresmoke.development.conf`, `etc/coresmoke.test.conf`, `etc/coresmoke.production.conf` — per-mode override files (selected by `MOJO_MODE`). Production uses STDERR logging and inherits the default; development sets `log_level => 'debug'`; test uses `db_path => 't/test.db'`.

### `lib/CoreSmoke/Controller/{Web,Api,JsonRpc,System,Ingest}.pm`

Empty stubs that subclass `Mojolicious::Controller`. Stub methods return 501 placeholders so `script/smoke routes` lists them. Each plan 03–07 fills these in.

### `lib/CoreSmoke/Schema/migrations.sql`

Empty `-- 1 up` / `-- 1 down` stub. Plan 02 fills this with the schema.

### `.gitignore` additions

```
/local/
/data/
/log/
/.cpanm/
```

`/data/` covers `smoke.db`, `smoke.db-wal`, `smoke.db-shm`, and the entire `data/reports/` tree. `cpanfile.snapshot` is **committed**.

### `.perlcriticrc`

```ini
severity = 5
verbose  = %f:%l:%c %m (%p)\n
```

Project-specific exclusions go here as they come up. CI fails on any violation (decision #44).

### `script/dev-setup` (optional)

`cpm install -L local/ && script/smoke morbo`. Useful as a developer affordance.

## Critical files to read first

- `legacy/api/bin/app.psgi`
- `legacy/api/lib/CoreSmokeDB.pm`
- `legacy/api/Makefile.PL` (for the existing dep set we are pruning)
- `legacy/api/environments/*.yml` (for config keys to preserve)

## Verification

1. `cpm install -L local/` succeeds.
2. `script/smoke routes` prints the registered routes (placeholder set, but populated).
3. `script/smoke get /system/ping` returns a 501 (stub) without exception.
4. `script/smoke morbo` starts on http://*:3000 and accepts a request.
5. `prove -lr t/` runs (no tests yet, just confirms the harness is wired).
6. `perlcritic --severity 5 lib/` reports no violations.

## Out of scope here

- Implementing controller bodies — see plans 03–07.
- Schema content — see plan 02.
- Docker — see plan 08.
