# Test Coverage Audit — 2026-04-26

## Summary

31 test files, 747 assertions. All pass. The test suite provides strong
end-to-end coverage for the **ingest pipeline**, **REST API**, **JSONRPC
dispatch**, **web routes**, and **search/matrix models**. Unit tests
cover helpers (plevel, duration, heatmap, XSS escaping, search compiler)
well. Security tests (CORS, CSP nonces, XSS, security headers, info
disclosure) are above average for a project this size.

**Estimated statement coverage**: ~85-90% of `lib/CoreSmoke/` by manual
analysis. Devel::Cover was available but could not produce data due to
prove forking (each test runs in a subprocess; Devel::Cover's in-process
collector loses the data). See "Coverage tooling" at the end for a fix.

---

## Module-by-Module Coverage Map

### Fully covered (no significant gaps)

| Module | Tests | Notes |
|--------|-------|-------|
| `Model::Plevel` | `02-plevel.t` | Corpus-driven via `plevel-corpus.tsv`. All branches including fallback from bare SHA and `_from_perl_id`. |
| `Model::ReportFiles` | `65-report-files.t` | `write`, `read_by_hash`, `has_file`, `path_for`, atomic-write behavior, missing-field undef. |
| `Model::DB` | `01-config.t` | Schema creation, pragmas, `report_hash` (exercised indirectly via ingest). |
| `Controller::System` | `10-system.t` | All 6 endpoints: ping, version, status, list_methods, healthz, readyz. |
| `Controller::Ingest` | `50-ingest.t`, `51-*`, `52-*`, `53-*`, `54-*` | Modern JSON, legacy form-encoded, gzip, cross-format pairs, duplicate detection, failure dedup, all three URL routes. The poster wire-format test (`54`) is exemplary. |
| `Controller::JsonRpc` | `40-jsonrpc.t` | Single dispatch, batch, unknown method, REST/JSONRPC parity, internal error hiding. |
| `JsonRpc::Methods` | `10-system.t`, `40-jsonrpc.t` | All system methods + API methods exercised through both REST and JSONRPC. |
| `Model::Search` (compiler) | `66-search-compile.t` | All filter dimensions, date range, GLOB patterns, AND/NOT negation, `latest`/`all` no-ops. |
| `Model::Matrix` | `67-matrix-empty.t`, `68-matrix-crosstab.t` | Empty DB, populated cross-tab, stdio inclusion, sort order, tie-breaking, submatrix with and without pversion filter. |

### Well covered with minor gaps

| Module | Tests | Covered | Gaps |
|--------|-------|---------|------|
| `Controller::Api` | `20-api-version.t`, `21-*`, `55-*` | version, latest, searchresults, searchparameters, matrix, submatrix, full_report_data, report_data, logfile, outfile, 404s, CORS, pagination caps | **`reports_from_id`** and **`reports_from_epoch`** endpoints have no dedicated tests. The model methods are exercised indirectly (`55-pagination-caps.t` calls `reports_from_id` once) but the HTTP routes `/api/reports_from_id/:rid` and `/api/reports_from_date/:epoch` are never hit via `$t->get_ok()`. |
| `Controller::Web` | `70-web.t`, `71-*`, `72-*`, `73-*`, `74-*`, `75-*`, `76-*`, `77-*`, `78-*` | All 10 routes: /, /latest, /search, /matrix, /submatrix, /about, /report/:rid, /file/*, 404 fallback. Filters, HTMX fragments, form-change vs scroll, hero stats, XSS. | **`/matrix` web page with populated data** is only tested via the API (`68-matrix-crosstab.t`); the HTML rendering of `/matrix` with failure rows is never asserted. **`/submatrix` web page** is tested for XSS but not for correct rendering of report rows. |
| `Model::Reports` | `50-*`, `51-latest-query.t`, `55-*`, `68-available-filters.t` | `latest()`, `full_report_data()`, `report_data()`, `searchresults()`, `searchparameters()`, `available_filter_values()`, `latest_perl_id()`, `version()`, `reports_from_id()` | **`reports_from_epoch()`** — never tested directly. **`logfile()`/`outfile()`** — tested indirectly (via API 404 paths and ingest), but no test ingests a fixture with non-empty log_file/out_file to exercise the happy path through `ReportFiles::read()` by report id. **`_hhmm()`** — only tested indirectly via template rendering. **`_summary_buckets()`** — only tested indirectly via `available_filter_values`. |
| `Model::Ingest` | `50-*`, `51-*`, `53-*`, `54-*` | `post_report()`, `_normalize()`, `_insert_report()`, `_insert_config()`, `_insert_result()`, `_insert_failures()`, smoke_config dedup | **`_to_iso_utc()`** — tested indirectly (fixture has ISO date already). No test with a non-ISO date string that exercises `Date::Parse` conversion. **Validation edge cases**: missing `sysinfo` hash, missing required fields like `hostname` (the `die` path in `_insert_report`). |
| `App.pm` | Various | startup, routes, all helpers, gzip decompression hook, security headers hook, CSP nonce | **`_config_file()`** fallback logic (MOJO_CONFIG env, mode-specific file, default file) — not directly tested. **`_resolve_path()`** — only tested indirectly. **`commify()` helper** — never tested. **`summary_desc()` helper** — never tested (used in full_report template tooltip). |

### Not covered at all

| Module/Area | Why it matters |
|-------------|---------------|
| `script/smoke` | Hypnotoad launcher script — low value to unit test, but no smoke test verifies it parses. |
| `script/migrate` | Schema migration CLI — could have a basic "runs without error" test. |
| `script/fix-plevels` | Recomputes all plevels — no test. Could be exercised by inserting a report with a wrong plevel, running the script logic, and verifying the correction. |
| `script/import-from-pgdump` | Legacy data importer — complex, tested manually. Lower priority. |
| `script/import-report-files-tarball` | Report files importer — no test. |
| OpenAPI spec completeness | `80-openapi.t` validates all spec paths are registered as routes, but does NOT validate that all routes are in the spec (one-way check). |

---

## End-to-End Test Coverage

The end-to-end tests use `Test::Mojo` with a real SQLite database and
real on-disk xz report files. This is excellent — no mocking of the
data layer.

### E2E flows tested

1. **Ingest -> Query -> Render**: fixture ingested via POST, then
   queried via REST API and rendered via web pages. Full stack exercised.
2. **Wire format matrix**: 8 scenarios covering all 3 URLs x 3 encoding
   formats (modern JSON, URI::Escape form, CGI::Util form) in `54-poster-wire-formats.t`.
3. **HTMX partial rendering**: form-change vs infinite-scroll fragments
   tested for `/latest` and `/search`.
4. **Security chain**: CORS, CSP nonces, X-Frame-Options, X-Content-Type-Options,
   XSS escaping in user_note/perl_id/io_env/submatrix params.
5. **Duplicate detection**: same report re-POSTed returns 409.

### E2E gaps

| Gap | Severity | Details |
|-----|----------|---------|
| No FAIL fixture | Medium | All tests use a single PASS fixture (`idefix-gff5bbe677.jsn`). There is no fixture with `summary = "FAIL(F)"` or test failures. The failure insertion code is tested via `53-ingest-failures.t` by calling `_insert_failures()` directly, but no end-to-end test ingests a complete failing report and verifies `/report/:rid` renders the failure table, compiler messages, etc. |
| No multi-config fixture | Medium | The single fixture has 2 configs, but both have PASS results. No fixture exercises the full_report view with mixed PASS/FAIL results across configs, which is the common case in production. |
| No log_file/out_file content | Medium | The fixture has empty `log_file` and `out_file`, so the `/file/log_file/:rid` and `/file/out_file/:rid` routes always return 404 in tests. The happy path (decompressing and rendering a real log) is never exercised E2E. |
| `/api/reports_from_id` route | Low | Model method called once in `55-pagination-caps.t`, but the HTTP route is never tested. |
| `/api/reports_from_date/:epoch` route | Low | Neither the route nor the model method `reports_from_epoch()` is tested. |
| POST to `/api/searchresults` | Low | The route accepts both GET and POST (`any [qw(GET POST)]`), but only GET is tested. |
| JSONRPC `post_report` method | Low | Never tested via JSONRPC — only via REST ingest routes. |
| JSONRPC `searchresults` with params | Low | Parity test uses empty DB; no test passes filter params through JSONRPC. |
| OpenAPI spec reverse check | Low | Tests verify spec paths exist as routes, but not that all routes exist in the spec. New routes could be undocumented. |
| `not_found` catchall | Low | No test hits an undefined route to verify the 404 template renders. |
| `readyz` unhealthy path | Low | No test for the 503 response when the DB is unavailable. |
| Dark mode rendering | Informational | CSS-only, not testable server-side. Documented in CLAUDE.md as requiring manual browser verification. |

---

## Security Test Coverage

Strong. Specific tests exist for:

- **XSS**: stored (user_note, perl_id, io_env) and reflected (submatrix test param) — `77-xss-escape.t`, `78-xss-raw-output.t`
- **CORS**: GET endpoints have wildcard, POST endpoints don't — `99-cors.t`
- **CSP**: nonce generation, nonce matching between header and HTML, nonce rotation — `99-security-headers.t`
- **Security headers**: X-Content-Type-Options, X-Frame-Options — `99-security-headers.t`
- **Info disclosure**: JSONRPC internal errors don't leak exception text — `40-jsonrpc.t`
- **Gzip bomb protection**: decompressed size limit tested — `52-ingest-gzip.t`

### Security gaps

| Gap | Severity |
|-----|----------|
| No SQL injection test | Low — all queries use parameterized `?` binds, but an explicit injection test against `/api/searchresults` with crafted params would document the defense. |
| No path traversal test for `/file/*` routes | Low — the routes use integer `:rid` which is safe, but no test verifies that non-integer rids are rejected. |
| No rate limiting test for ingest | Informational — no rate limiting exists; documented for awareness. |

---

## Recommendations (prioritized)

### High value, low effort

1. **Add a FAIL fixture** (`t/data/fail-report.jsn`) with real test
   failures, non-empty `log_file` and `out_file`. Use it to E2E test:
   - `/report/:rid` renders the failure table and compiler messages
   - `/file/log_file/:rid` returns 200 with content
   - `/matrix` web page shows failure rows

2. **Test `reports_from_epoch`** — a 3-line test: insert a report,
   call the endpoint with an epoch before the smoke_date, verify the
   report id is returned.

3. **Test `reports_from_id` HTTP route** — similarly trivial.

4. **Test `commify` and `summary_desc` helpers** — pure functions,
   5 minutes to add.

### Medium value

5. **Reverse OpenAPI check** — in `80-openapi.t`, verify that every
   non-catchall route has a corresponding spec path. Catches undocumented
   endpoints.

6. **Test the 404 catchall** — `$t->get_ok('/no-such-page')->status_is(404)`.

7. **Test `_to_iso_utc` with non-ISO input** — e.g., ingest a fixture
   with `smoke_date: "Jul 31 2022 01:05:08"` and verify it normalizes.

8. **Fix Devel::Cover integration** — add a `cover` Makefile target
   that uses `HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t/` instead
   of `perl -MDevel::Cover prove`. The `HARNESS_PERL_SWITCHES` approach
   passes the flag to each forked test process, solving the data
   collection problem.

### Lower priority

9. **Script smoke tests** — basic `perl -c script/migrate` etc. to
   verify they compile.

10. **POST to `/api/searchresults`** — trivial to add alongside the
    existing GET tests.

11. **JSONRPC searchresults with filters** — extend `40-jsonrpc.t`.

---

## Coverage Tooling Fix

The `make cover` target currently fails because `cover` is not in PATH.
Also, Devel::Cover needs `HARNESS_PERL_SWITCHES` to instrument forked
test processes. Recommended Makefile target:

```makefile
cover:
	rm -rf cover_db
	HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t/
	perl -MDevel::Cover -e 'Devel::Cover::Report::Text->report( \
	    Devel::Cover::DB->new(db => "cover_db"))'
```

---

## Test Architecture Notes

- **TestApp.pm** is clean and minimal. `reset_db()` deletes the DB +
  WAL/SHM files + reports dir between tests. Sequential `prove -lr`
  ensures no parallel contention.
- **Single fixture** (`idefix-gff5bbe677.jsn`) is used everywhere.
  This is pragmatic but limits failure-path coverage. A second fixture
  with failures would unlock significant additional E2E coverage.
- **No mocks** of the data layer — tests hit real SQLite and real xz
  files. This is the right choice for an app this size.
- **Insert helpers** in `51-latest-query.t`, `55-pagination-caps.t`,
  `68-matrix-crosstab.t`, `76-hero-stats.t` duplicate a `sub insert_report`.
  Could be extracted to TestApp.pm, but the duplication is harmless.
