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

# templates / web
requires 'Mojolicious::Plugin::Config';

# misc
requires 'JSON::PP',              '>= 4.16';
requires 'Digest::MD5';
requires 'Date::Parse';
requires 'DateTime';
requires 'DateTime::Format::SQLite';

on 'develop' => sub {
    requires 'Test::More',        '>= 1.302';
    requires 'Test::Mojo';
    requires 'Test::Deep';
    requires 'Test::Warnings';
};
```

### `script/smoke`

Mojolicious launcher (`#!/usr/bin/env perl`, `use lib …; use Mojolicious::Commands; Mojolicious::Commands->start_app('Perl5::CoreSmoke::App')`). Mark executable.

### `lib/Perl5/CoreSmoke/App.pm`

`Mojolicious` subclass. In `startup`:

1. Load config via `$self->plugin('Config' => { file => $self->_config_file })`. Resolve config file from `MOJO_CONFIG` or `etc/coresmoke.conf` relative to `$self->home`.
2. Resolve the SQLite path: `$ENV{SMOKE_DB_PATH} // $self->config->{db_path} // $self->home->child('smoke.db')`.
3. Register a `sqlite` helper that returns a memoized `Mojo::SQLite` configured with the migrations file at `lib/Perl5/CoreSmoke/Schema/migrations.sql`.
4. `$self->sqlite->migrations->migrate` on startup so a freshly mounted empty `smoke.db` self-initializes.
5. Mount controllers (defer detail to plans 03–07): `$r->get('/system/...') ...`, `$r->any([qw(GET POST)] => '/api')->to('JsonRpc#dispatch')`, `$r->get('/api/...')`, `$r->get('/')->to('Web#latest')`, etc.
6. Set `$self->log->level('info')` (override per env in config).
7. Hypnotoad config: `$self->config->{hypnotoad} //= { listen => ['http://*:8080'], workers => 4 }`.

Use `use v5.42; use experimental qw(signatures);` at the top.

### `etc/coresmoke.conf`

Single Mojo config hash:

```perl
{
    db_path  => $ENV{SMOKE_DB_PATH} // 'smoke.db',
    log_level => $ENV{SMOKE_LOG_LEVEL} // 'info',
    cors_allow_origin => '*',          # legacy default
    hypnotoad => {
        listen   => ['http://*:8080'],
        workers  => 4,
        clients  => 100,
        accepts  => 100,
        graceful_timeout => 30,
        proxy    => 1,
    },
};
```

Per-env override files (`etc/coresmoke.development.conf`, `etc/coresmoke.test.conf`) shipped as separate files; selection via `MOJO_MODE`.

### `lib/Perl5/CoreSmoke/Controller/Web.pm`, `Controller/Api.pm`, `Controller/JsonRpc.pm`, `Controller/System.pm`, `Controller/Ingest.pm`

Empty stubs that subclass `Mojolicious::Controller`. Stub methods return 501 placeholders so `script/smoke routes` lists them. Each plan 03–07 fills these in.

### `lib/Perl5/CoreSmoke/Schema/migrations.sql`

Empty `-- 1 up` / `-- 1 down` stub. Plan 02 fills this with the schema.

### `.gitignore` additions

```
/local/
/smoke.db
/smoke.db-shm
/smoke.db-wal
/log/
/.cpanm/
/cpanfile.snapshot
```

(Keep `cpanfile.snapshot` ignored or committed — recommend committed for reproducibility, but it's optional.)

### `script/dev-setup` (optional)

A small wrapper: `cpm install -L local/ && script/smoke get /system/ping`. Useful as a developer affordance.

## Critical files to read first

- `legacy/api/bin/app.psgi`
- `legacy/api/lib/Perl5/CoreSmokeDB.pm`
- `legacy/api/Makefile.PL` (for the existing dep set we are pruning)
- `legacy/api/environments/*.yml` (for config keys to preserve in `etc/coresmoke.conf`)

## Verification

1. `cpm install -L local/` succeeds.
2. `perl -Ilocal/lib/perl5 -Ilib script/smoke routes` prints the registered routes (placeholder set, but populated).
3. `perl -Ilocal/lib/perl5 -Ilib script/smoke get /system/ping` returns a 501 (or whatever stub) without exception.
4. `perl -Ilocal/lib/perl5 -Ilib script/smoke prefork --listen http://*:8080` boots and accepts a request.
5. `prove -lr t/` runs (no tests yet, just confirms the harness is wired).

## Out of scope here

- Implementing controller bodies — see plans 03–07.
- Schema content — see plan 02.
- Docker — see plan 08.
