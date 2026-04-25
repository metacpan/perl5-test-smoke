# 02 — Database (SQLite)

## Goal

Translate the PostgreSQL schema in `legacy/sql/coresmokedb.sql` to a SQLite-compatible migration that Mojo::SQLite can apply on first boot of `smoke.db`. Port the `git_describe_as_plevel()` PL/pgSQL function to Perl with byte-for-byte parity.

## Schema source of truth

`legacy/sql/coresmokedb.sql`. Tables to recreate:

| Table | Notes |
|------|-------|
| `report` | Largest. Contains BLOB columns (`manifest_msgs`, `compiler_msgs`, `log_file`, `out_file`, `nonfatal_msgs`) and a generated `plevel` column. |
| `config` | FK → `report.id`. |
| `result` | FK → `config.id`. |
| `failure` | UNIQUE(test, status, extra). |
| `failures_for_env` | Junction; FKs → `result.id`, `failure.id`; UNIQUE(result_id, failure_id). |
| `smoke_config` | UNIQUE(md5). |
| `tsgateway_config` | UNIQUE(name). One row holds `dbversion`. |

## Migration file

`lib/Perl5/CoreSmoke/Schema/migrations.sql` — single Mojo::SQLite migrations file:

```sql
-- 1 up

CREATE TABLE smoke_config (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    md5     TEXT    NOT NULL UNIQUE,
    config  TEXT
);

CREATE TABLE report (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    sconfig_id        INTEGER REFERENCES smoke_config(id),
    duration          INTEGER,
    config_count      INTEGER,
    reporter          TEXT,
    reporter_version  TEXT,
    smoke_perl        TEXT,
    smoke_revision    TEXT,
    smoke_version     TEXT,
    smoker_version    TEXT,
    smoke_date        TEXT NOT NULL,            -- ISO 8601 UTC
    perl_id           TEXT NOT NULL,
    git_id            TEXT NOT NULL,
    git_describe      TEXT NOT NULL,
    applied_patches   TEXT,
    hostname          TEXT NOT NULL,
    architecture      TEXT NOT NULL,
    osname            TEXT NOT NULL,
    osversion         TEXT NOT NULL,
    cpu_count         TEXT,
    cpu_description   TEXT,
    username          TEXT,
    test_jobs         TEXT,
    lc_all            TEXT,
    lang              TEXT,
    user_note         TEXT,
    manifest_msgs     BLOB,
    compiler_msgs     BLOB,
    skipped_tests     TEXT,
    log_file          BLOB,
    out_file          BLOB,
    harness_only      TEXT,
    harness3opts      TEXT,
    summary           TEXT NOT NULL,
    smoke_branch      TEXT DEFAULT 'blead',
    nonfatal_msgs     BLOB,
    plevel            TEXT NOT NULL,            -- populated in Perl on insert
    UNIQUE(git_id, smoke_date, duration, hostname, architecture)
);

CREATE INDEX report_architecture_idx           ON report(architecture);
CREATE INDEX report_hostname_idx               ON report(hostname);
CREATE INDEX report_osname_idx                 ON report(osname);
CREATE INDEX report_osversion_idx              ON report(osversion);
CREATE INDEX report_perl_id_idx                ON report(perl_id);
CREATE INDEX report_plevel_idx                 ON report(plevel);
CREATE INDEX report_smoke_date_idx             ON report(smoke_date);
CREATE INDEX report_plevel_hostname_idx        ON report(hostname, plevel);
CREATE INDEX report_smokedate_hostname_idx     ON report(hostname, smoke_date);
CREATE INDEX report_smokedate_plevel_hostname  ON report(hostname, plevel, smoke_date);

CREATE TABLE config (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    report_id   INTEGER NOT NULL REFERENCES report(id) ON DELETE CASCADE,
    arguments   TEXT NOT NULL,
    debugging   TEXT NOT NULL,
    started     TEXT,
    duration    INTEGER,
    cc          TEXT,
    ccversion   TEXT
);
CREATE INDEX config_report_id_idx ON config(report_id);

CREATE TABLE result (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    config_id      INTEGER NOT NULL REFERENCES config(id) ON DELETE CASCADE,
    io_env         TEXT NOT NULL,
    locale         TEXT,
    summary        TEXT NOT NULL,
    statistics     TEXT,
    stat_cpu_time  REAL,
    stat_tests     INTEGER
);
CREATE INDEX result_config_id_idx ON result(config_id);

CREATE TABLE failure (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    test    TEXT NOT NULL,
    status  TEXT NOT NULL,
    extra   TEXT,
    UNIQUE(test, status, extra)
);

CREATE TABLE failures_for_env (
    result_id   INTEGER NOT NULL REFERENCES result(id)  ON DELETE CASCADE,
    failure_id  INTEGER NOT NULL REFERENCES failure(id) ON DELETE CASCADE,
    UNIQUE(result_id, failure_id)
);

CREATE TABLE tsgateway_config (
    id     INTEGER PRIMARY KEY AUTOINCREMENT,
    name   TEXT NOT NULL UNIQUE,
    value  TEXT
);

INSERT INTO tsgateway_config (name, value) VALUES ('dbversion', '3');

-- 1 down

DROP TABLE failures_for_env;
DROP TABLE failure;
DROP TABLE result;
DROP TABLE config;
DROP TABLE report;
DROP TABLE smoke_config;
DROP TABLE tsgateway_config;
```

### Postgres → SQLite type translations

- `character varying` → `TEXT`
- `integer` → `INTEGER`
- `bytea` → `BLOB`
- `timestamp with time zone` → `TEXT` (ISO 8601 UTC, e.g. `2024-05-08T10:23:11Z`)
- `double precision` → `REAL`
- Sequences (`*_id_seq` + `nextval`) → `INTEGER PRIMARY KEY AUTOINCREMENT`
- `STORED GENERATED plevel` → ordinary `TEXT NOT NULL`, populated by `Model::Plevel` on insert

### FK enforcement

Mojo::SQLite enables `PRAGMA foreign_keys = ON` automatically per connection. Confirm in `Model::DB` and assert in tests.

## `Model::Plevel`

Port `git_describe_as_plevel()` (`legacy/sql/coresmokedb.sql:46-74`) to Perl. The function:

1. Strip leading `v`.
2. Strip trailing `-g.+` suffix.
3. Split on `[.-]` into up to 4 parts.
4. `parts[0] . '.' . zero-pad(parts[1], 3) . zero-pad(parts[2], 3)`
5. If only 3 parts, append `'0'` as parts[3].
6. If `parts[3] =~ /RC/`, append `parts[3]`; else append `'zzz'`.
7. Append zero-padded last part (3 wide).

Implementation:

```perl
package Perl5::CoreSmoke::Model::Plevel;
use v5.42;
use experimental qw(signatures);

sub from_git_describe ($describe) {
    my $clean = $describe // '';
    $clean =~ s/^v//;
    $clean =~ s/-g.+$//;
    my @parts = split /[.\-]/, $clean;
    push @parts, '0' if @parts == 3;

    my $plevel = sprintf '%s.%03d%03d', $parts[0], $parts[1] // 0, $parts[2] // 0;
    $plevel .= ($parts[3] =~ /RC/ ? $parts[3] : 'zzz');
    $plevel .= sprintf '%03d', $parts[-1] =~ /(\d+)/ ? $1 : 0;
    return $plevel;
}

1;
```

A parity test (see plan 09) runs a corpus of `git_describe` strings through both this module and a checked-in expected-output table extracted from the live PG database. Adjust the regex/edge cases until parity holds.

## `Model::DB`

Mojolicious helper around `Mojo::SQLite`. Responsibilities:

- Construct from `db_path` config value.
- Attach migrations file path.
- Expose `db()` for short-lived `Mojo::SQLite::Database` handles.
- `pragma_check()` for tests: assert `foreign_keys = 1`, `journal_mode = wal`.

## Critical files to read

- `legacy/sql/coresmokedb.sql:46-74`         (plevel function source)
- `legacy/sql/coresmokedb.sql:175-213`       (report table)
- `legacy/sql/coresmokedb.sql:380-475`       (FK and unique constraints)
- `legacy/api/lib/Perl5/CoreSmokeDB/Client/Database.pm`  (how schema is consumed)
- `legacy/api/t/coresmokedb.sqlite`          (sample SQLite DB; for column shape reference only)

## Verification

1. `script/smoke eval 'app->sqlite->migrations->migrate'` against an empty `smoke.db` exits 0 and creates all tables.
2. `sqlite3 smoke.db '.schema'` matches the migration above.
3. `script/smoke eval 'app->sqlite->db->query("PRAGMA foreign_keys")->hash'` returns `{ foreign_keys => 1 }`.
4. Plevel parity test: a corpus of ≥30 `git_describe` strings (extracted via `psql -c "select distinct git_describe, plevel from report limit 200"` from a legacy DB if available, or hand-curated) all map to the legacy plevel string.
5. Inserting a sample report via raw SQL with a hand-computed plevel succeeds; FK violations are rejected.
