# 10 — Legacy data migration (deferred)

## Status: deferred per user decision

The 2.0 cutover starts with an empty `smoke.db` and an empty `data/reports/` tree. The existing PostgreSQL database (~5.5M reports, ~850K results, ~550K configs) plus its bytea content stays on the legacy stack until ops/the user decides to migrate. This plan exists so the work isn't forgotten.

## What "done" would look like

A one-shot importer script `script/import-from-pg`:

```
script/import-from-pg \
    --pg-dsn 'dbi:Pg:dbname=coresmokedb;host=oldserver' \
    --pg-pass-file ~/.pgpass \
    --target /data/smoke.db \
    --reports-dir /data/reports \
    --batch 1000 \
    [--since '2024-01-01']
```

Running this on a freshly initialized `smoke.db` and empty `data/reports/`:

1. Reads `report` rows in chunks ordered by id, with all FK-related rows joined or fetched per-batch.
2. **For each row, the five legacy bytea fields (`log_file`, `out_file`, `manifest_msgs`, `compiler_msgs`, `nonfatal_msgs`) are written to disk** under `data/reports/<sharded-hash>/<field>.xz` (xz-compressed). The bytea bytes go straight to xz; no intermediate decode/encode.
3. Computes `report_hash = md5_hex(git_id . "\0" . smoke_date . "\0" . duration . "\0" . hostname . "\0" . architecture)` for each row and stores it.
4. Computes `plevel` via `CoreSmoke::Model::Plevel::from_git_describe` and asserts it matches the value PG already stored — fail loudly on mismatches (this is also a parity test of the Perl port).
5. Normalizes timestamps (`timestamptz` → ISO 8601 UTC TEXT).
6. Writes via `INSERT OR IGNORE` so the importer is resumable.
7. Translates sequence-derived ids: SQLite assigns its own ids; the importer **preserves legacy ids** so URLs like `/report/12345` still resolve. `INSERT INTO report(id, ...)` with the original id, then bump `sqlite_sequence` to MAX(id) + 1 at the end.
8. Verifies row counts per table after import; verifies the on-disk file count matches the count of rows that had non-empty bytea fields in PG.

## Hard parts to plan for when this is picked up

- **Throughput**: 5.5M rows is meaningful but not huge for SQLite. Disk-bound mostly — expect 30–90 minutes depending on disk and bytea sizes (the legacy `log_file`/`out_file` blobs dominate). Use `BEGIN`/`COMMIT` per 1000-row batch and `PRAGMA synchronous=OFF; PRAGMA journal_mode=MEMORY` *during* import (revert after).
- **Sharding load**: ~5.5M directories, three-level sharded — each leaf typically holds one report. Filesystem inode count matters more than depth here; ext4 / xfs handle it fine.
- **xz compression cost**: at level 6 (default) ~10 ms per moderately sized log file. Run with `--workers=N` if needed. Consider `xz -1` during import for speed; the compression ratio difference is small.
- **bytea → xz fidelity**: PG bytea is bytes. Pass them through xz as-is, no encoding step. The legacy encode-as-utf-8 quirk is irrelevant in 2.0 since we never store BLOBs.
- **MD5 collisions in `smoke_config`**: legacy table dedupes by md5; importer must preserve `smoke_config.id` so `report.sconfig_id` FKs match.
- **plevel discrepancies**: if the Perl port disagrees with the PG function on any real row, fix the Perl port — do not silently accept the discrepancy. Add the failing `git_describe` to `t/data/plevel-corpus.tsv`.
- **Cutover**: write-pause the legacy stack, run the importer with no `--since`, verify counts, flip DNS / Fastly. Brief overlap; after cutover, legacy stack is read-only.
- **Rollback**: keep the source PG dump and a `script/import-from-pg --resume` mode so a partial migration can be retried. The on-disk files are append-only by hash, so re-running is safe.

## Critical files to read when this is picked up

- `legacy/sql/coresmokedb.sql` (final reference for source schema)
- `legacy/api/lib/CoreSmokeDB/Client/Database.pm` (semantics of every column)
- `lib/CoreSmoke/Schema/migrations.sql` (target schema; note dropped BLOBs and added `report_hash`)
- `lib/CoreSmoke/Model/Plevel.pm` (must match PG output for every existing `git_describe`)
- `lib/CoreSmoke/Model/ReportFiles.pm` (path computation + xz I/O)

## Verification (when implemented)

1. Importer runs end-to-end against a snapshot dump and reports the same row counts as `pg_class` for each table.
2. For 100 random `id`s, `GET /api/full_report_data/:id` on the new stack returns a payload `is_deeply` to the legacy stack's response.
3. For 100 random `id`s, `GET /api/logfile/:id` returns the same bytes as the legacy `GET /api/logfile/:id`.
4. Plevel values in `report` table are byte-equal between source PG and target SQLite.
5. Re-running the importer is a no-op (idempotency).
6. Disk usage of `data/reports/` after import is roughly 1/5 of the source bytea total (xz ratio for log files).

## Out of scope

- Streaming/CDC replication during the cutover window.
- Post-import full-text indexes (we have no FTS today; not needed).
- Migration of historical access logs / metrics.
