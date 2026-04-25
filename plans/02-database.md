# 02 — Database (SQLite)

## Goal

Translate the PostgreSQL schema in `legacy/sql/coresmokedb.sql` to a SQLite-compatible migration that Mojo::SQLite applies on first boot of `smoke.db`. **Drop the five bytea columns from `report` — those bytes live on disk** (decision #30, see plan 05). Port `git_describe_as_plevel()` to Perl with parity against a hand-curated corpus.

## Schema source of truth

`legacy/sql/coresmokedb.sql`. Tables to recreate:

| Table | Notes |
|------|-------|
| `report` | Largest. **No BLOB columns in 2.0.** New `report_hash` UNIQUE column. |
| `config` | FK → `report.id` `ON DELETE CASCADE`. |
| `result` | FK → `config.id` `ON DELETE CASCADE`. |
| `failure` | UNIQUE(test, status, extra). |
| `failures_for_env` | Junction; FKs `ON DELETE CASCADE` to `result.id` and `failure.id`; UNIQUE(result_id, failure_id). |
| `smoke_config` | UNIQUE(md5). |
| `tsgateway_config` | UNIQUE(name). One row holds `dbversion = '4'`. |

## Migration file

`lib/CoreSmoke/Schema/migrations.sql` — single Mojo::SQLite migrations file:

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
    skipped_tests     TEXT,
    harness_only      TEXT,
    harness3opts      TEXT,
    summary           TEXT NOT NULL,
    smoke_branch      TEXT DEFAULT 'blead',
    plevel            TEXT NOT NULL,            -- populated in Perl on insert
    report_hash       TEXT NOT NULL UNIQUE,     -- md5(git_id, smoke_date, duration, hostname, architecture)
    UNIQUE(git_id, smoke_date, duration, hostname, architecture)
);
-- NOTE: the legacy bytea columns log_file, out_file, manifest_msgs, compiler_msgs, nonfatal_msgs
--       are NOT in 2.0. Their content lives on disk under data/reports/<sharded-hash>/<field>.xz.

CREATE INDEX report_architecture_idx          ON report(architecture);
CREATE INDEX report_hostname_idx              ON report(hostname);
CREATE INDEX report_osname_idx                ON report(osname);
CREATE INDEX report_osversion_idx             ON report(osversion);
CREATE INDEX report_perl_id_idx               ON report(perl_id);
CREATE INDEX report_plevel_idx                ON report(plevel);
CREATE INDEX report_smoke_date_idx            ON report(smoke_date);
CREATE INDEX report_plevel_hostname_idx       ON report(hostname, plevel);
CREATE INDEX report_smokedate_hostname_idx    ON report(hostname, smoke_date);
CREATE INDEX report_smokedate_plevel_hostname ON report(hostname, plevel, smoke_date);

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

INSERT INTO tsgateway_config (name, value) VALUES ('dbversion', '4');

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
- ~~`bytea` → `BLOB`~~ — **all bytea columns dropped**; content on disk
- `timestamp with time zone` → `TEXT` (ISO 8601 UTC, e.g. `2024-05-08T10:23:11Z`)
- `double precision` → `REAL`
- Sequences (`*_id_seq` + `nextval`) → `INTEGER PRIMARY KEY AUTOINCREMENT`
- `STORED GENERATED plevel` → ordinary `TEXT NOT NULL`, populated by `Model::Plevel` on insert

### FK enforcement and journal mode

Mojo::SQLite enables `PRAGMA foreign_keys = ON` automatically per connection. WAL journal mode is the default. Confirm both in `Model::DB::pragma_check()` and assert in `t/01-config.t`.

## `Model::Plevel`

Port `git_describe_as_plevel()` (`legacy/sql/coresmokedb.sql:46-74`) to Perl, byte-faithful to the PG function. The function:

1. Strip leading `v`.
2. Strip trailing `-g.+` suffix.
3. Split on `[.-]` into parts.
4. `parts[0] . '.' . lpad(parts[1], 3, '0') . lpad(parts[2], 3, '0')`.
5. If only 3 parts, append `'0'` as parts[3].
6. If `parts[3] =~ /RC/`, append `parts[3]` verbatim; else append `'zzz'`.
7. Append `lpad(parts[-1], 3, '0')` — Postgres `lpad` semantics: pad on the left with `'0'` if shorter than 3, **truncate from the right** if longer than 3. So when `parts[-1]` is something like `RC1` (already 3 chars), it is appended as-is, producing `...RC1RC1`.

Implementation:

```perl
package CoreSmoke::Model::Plevel;
use v5.42;
use warnings;
use experimental qw(signatures);

sub from_git_describe ($describe) {
    my $clean = $describe // '';
    $clean =~ s/^v//;
    $clean =~ s/-g.+$//;
    my @parts = split /[.\-]/, $clean;
    push @parts, '0' if @parts == 3;

    my $plevel = ($parts[0] // '') . '.'
               . _lpad($parts[1] // '', 3, '0')
               . _lpad($parts[2] // '', 3, '0');

    $plevel .= (defined $parts[3] && $parts[3] =~ /RC/)
        ? $parts[3]
        : 'zzz';

    $plevel .= _lpad($parts[-1] // '', 3, '0');
    return $plevel;
}

# PG lpad(str, len, fill): left-pad with `fill` if shorter than `len`,
# truncate from the right if longer.
sub _lpad ($str, $len, $fill) {
    return substr($str, 0, $len) if length($str) > $len;
    return $fill x ($len - length($str)) . $str;
}

1;
```

A parity test (see plan 09) runs each entry of `t/data/plevel-corpus.tsv` through this module and asserts the output matches. The corpus is **hand-curated** (decision #7). Expected outputs were generated by the actual PG function (cross-checked against `script/import-from-pgdump` against the production dump). At least these variants:

```
5.42.0                          5.042000zzz000
v5.42.0                         5.042000zzz000
v5.42.0-RC1                     5.042000RC1RC1
v5.42.0-RC2                     5.042000RC2RC2
v5.41.10                        5.041010zzz000
v5.41.10-12-gabc1234            5.041010zzz012
v5.40.2                         5.040002zzz000
v5.40.0-RC3-5-gdef5678          5.040000RC3005
... (~30 entries total)
```

The bare-RC-tag rows (`v5.42.0-RC1` → `5.042000RC1RC1`) look surprising but are exactly what the legacy PG `lpad(parts[last], 3, '0')` produced when `parts[last]` was already `'RC1'`. Matching this byte-for-byte is required so plevel-keyed URLs and existing client expectations keep working post-migration.

If a real-world `git_describe` ever fails the test in production, add it to the corpus and fix `from_git_describe` until it passes.

## `Model::DB`

Mojolicious helper around `Mojo::SQLite`. Responsibilities:

- Construct from `db_path` config value.
- Attach migrations file path (`lib/CoreSmoke/Schema/migrations.sql`).
- Run `migrate` on app startup.
- Expose `db()` for short-lived `Mojo::SQLite::Database` handles.
- `pragma_check()` for tests: assert `foreign_keys = 1`, `journal_mode = wal`.
- `report_hash($data)` helper: `md5_hex(join "\0", @{$data}{qw/git_id smoke_date duration hostname architecture/})`.

## Critical files to read

- `legacy/sql/coresmokedb.sql:46-74`         (plevel function source)
- `legacy/sql/coresmokedb.sql:175-213`       (report table — note we drop bytea columns)
- `legacy/sql/coresmokedb.sql:380-475`       (FK and unique constraints)
- `legacy/api/lib/CoreSmokeDB/Client/Database.pm`  (DAO behavior to mirror)

## Verification

1. `script/smoke eval 'app->sqlite->migrations->migrate'` against an empty `smoke.db` exits 0 and creates all tables.
2. `sqlite3 data/smoke.db '.schema report'` shows **no** `manifest_msgs`, `compiler_msgs`, `log_file`, `out_file`, or `nonfatal_msgs` columns and **does** show `report_hash TEXT NOT NULL`.
3. `sqlite3 data/smoke.db 'SELECT value FROM tsgateway_config WHERE name=\"dbversion\"'` returns `4`.
4. `script/smoke eval 'app->sqlite->db->query("PRAGMA foreign_keys")->hash'` returns `{ foreign_keys => 1 }`.
5. `script/smoke eval 'app->sqlite->db->query("PRAGMA journal_mode")->hash'` returns `{ journal_mode => 'wal' }`.
6. Plevel parity test: every entry of `t/data/plevel-corpus.tsv` passes (`prove -lv t/02-plevel.t`).
7. Inserting a sample report via raw SQL succeeds; a duplicate insert (same composite tuple) fails with `UNIQUE constraint failed: report.git_id, report.smoke_date, ...`.
