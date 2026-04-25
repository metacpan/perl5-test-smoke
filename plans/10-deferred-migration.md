# 10 — Legacy data migration (deferred)

## Status: deferred per user decision

The 2.0 cutover starts with an empty `smoke.db`. The existing PostgreSQL database (~5.5M reports, ~850K results, ~550K configs) keeps running on the legacy stack until ops/the user decides to migrate. This plan exists so the work isn't forgotten.

## What "done" would look like

A one-shot importer script `script/import-from-pg`:

```
script/import-from-pg \
    --pg-dsn 'dbi:Pg:dbname=coresmokedb;host=oldserver' \
    --pg-pass-file ~/.pgpass \
    --target /data/smoke.db \
    --batch 1000 \
    [--since '2024-01-01']
```

Running this on a freshly migrated `smoke.db`:

1. Reads `report` rows in chunks ordered by id, with all FK-related rows joined or fetched per-batch.
2. For each row, normalizes types (`timestamptz` → ISO 8601, `bytea` → BLOB).
3. Computes `plevel` via `Perl5::CoreSmoke::Model::Plevel::from_git_describe` and asserts it matches the value PG already stored — fail loudly on mismatches (this is also a parity test of the Perl port).
4. Writes via `INSERT OR IGNORE` so the importer is resumable.
5. Translates sequence-derived ids: SQLite assigns its own ids; the importer needs to **preserve legacy ids** so URLs like `/report/12345` still resolve. Use `INSERT INTO report(id, ...)` with the original id, then bump `sqlite_sequence` to MAX(id) + 1 at the end.
6. Verifies row counts per table after import.

## Hard parts to plan for when this is picked up

- **Throughput**: 5.5M rows is meaningful but not huge for SQLite. Expect 10–60 minutes depending on disk; use `BEGIN`/`COMMIT` per 1000-row batch and `PRAGMA synchronous=OFF; PRAGMA journal_mode=MEMORY` *during* the import (revert after).
- **BLOB sizing**: `log_file` and `out_file` can be large. Stream them per-row, don't load all at once.
- **MD5 collisions in `smoke_config`**: the legacy table dedupes by md5; the importer must preserve `smoke_config.id` so report `sconfig_id` FKs still match.
- **plevel discrepancies**: if the Perl port disagrees with the PG function on any real row, fix the Perl port — do not silently accept the discrepancy.
- **Cutover**: write-pause the legacy stack, run the importer with no `--since`, verify counts, flip DNS / Fastly. The two stacks stay simultaneously writable only during a brief overlap; after cutover, the legacy stack is read-only.
- **Rollback**: keep the source PG dump and a `script/import-from-pg --resume` mode so a partial migration can be retried.

## Critical files to read when this is picked up

- `legacy/sql/coresmokedb.sql` (final reference for source schema)
- `legacy/api/lib/Perl5/CoreSmokeDB/Client/Database.pm` (semantics of every column)
- `lib/Perl5/CoreSmoke/Schema/migrations.sql` (target schema; note differences from PG)
- `lib/Perl5/CoreSmoke/Model/Plevel.pm` (must match PG output for every existing `git_describe`)

## Verification (when implemented)

1. Importer runs end-to-end against a snapshot dump and reports the same counts as `pg_class` for each table.
2. For 100 random `id`s, `GET /api/full_report_data/:id` on the new stack returns a payload `is_deeply` to the legacy stack's response.
3. Plevel values in `report` table are byte-equal between source PG and target SQLite.
4. Re-running the importer is a no-op (idempotency).

## Out of scope

- Streaming/CDC replication during the cutover window.
- Post-import full-text indexes (we have no FTS today; not needed).
