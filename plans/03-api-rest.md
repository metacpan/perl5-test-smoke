# 03 — REST API controllers

## Goal

Re-expose every legacy `/api/*` and `/system/*` REST path with byte-compatible request/response shapes, served by `Controller::Api`, `Controller::System`, and `Controller::Ingest`. **Built in the same milestone as the JSONRPC dispatcher (plan 04)** because both share the `JsonRpc/Methods.pm` registry and the same DAO helpers.

## Route map

### `Controller::System` (`/system`, `/healthz`, `/readyz`)

| Verb | Path | DAO method | Notes |
|------|------|-----------|-------|
| GET | `/healthz` | n/a | Always 200 if process is alive (decision #34). |
| GET | `/readyz` | n/a | 200 only if `SELECT 1` against SQLite succeeds; 503 otherwise. |
| GET | `/system/ping` | `ping` | returns `"pong"` plain |
| GET | `/system/version` | `version` | `{software_version}` |
| GET | `/system/status` | `status` | `{app_version, app_name, active_since, hostname, running_pid, dancer2 (carry key, value = Mojolicious version), rpc_plugin}` |
| GET | `/system/methods` | `list_methods` | full method list |
| GET | `/system/methods/:plugin` | `list_methods` | filtered by plugin name |

### `Controller::Api` (`/api`)

| Verb | Path | DAO method (`Model::Reports`) | Notes |
|------|------|-------------------------------|-------|
| GET | `/api/version` | `version` | `{version, schema_version, db_version}` (db_version = `4`) |
| GET | `/api/latest` | `latest` | `{reports[], report_count, latest_plevel, rpp, page}` (default `rpp=25`, decision #26) |
| GET | `/api/full_report_data/:rid` | `full_report_data` | full expanded report; 404 on miss |
| GET | `/api/report_data/:rid` | `report_data` | report+linked data hashref; 404 on miss |
| GET | `/api/logfile/:rid` | `logfile` | `{file: <decoded log_file>}` — reads `data/reports/<sharded>/log_file.xz` and stream-decompresses |
| GET | `/api/outfile/:rid` | `outfile` | `{file: <decoded out_file>}` — **legacy `/api/outfle` typo dropped** (decision #9) |
| GET | `/api/matrix` | `matrix` | failure matrix |
| GET | `/api/submatrix` | `submatrix` | params `test` (req), `pversion` (opt) |
| GET | `/api/searchparameters` | `searchparameters` | filter dropdown source |
| GET, POST | `/api/searchresults` | `searchresults` | full filter set + paging (default `reports_per_page=25`) |
| GET | `/api/reports_from_id/:rid` | `reports_from_id` | optional `?limit=N` (default 100) |
| GET | `/api/reports_from_date/:epoch` | `reports_from_epoch` | |
| POST | `/api/report` | `post_report` | covered in plan 05 |
| POST | `/api/old_format_reports` | `post_report` (legacy adapter) | covered in plan 05 |
| POST | `/report` | `post_old_format_report` | **built-in alias** for the legacy Fastly redirect target (decision #10) |
| GET | `/api/openapi/web.json` | n/a | spec, served as JSON |
| GET | `/api/openapi/web.yaml` | n/a | spec, served as YAML |
| GET | `/api/openapi/web` | n/a | spec, served as `text/plain` |

## Controller pattern

```perl
package CoreSmoke::Controller::Api;
use v5.42;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub latest ($c) {
    return $c->render(json => $c->app->reports->latest);
}

sub full_report_data ($c) {
    my $rid  = $c->stash('rid');
    my $data = $c->app->reports->full_report_data($rid)
        // return $c->render(status => 404, json => { error => 'Report not found.' });
    return $c->render(json => $data);
}

sub logfile ($c) {
    my $rid = $c->stash('rid');
    my $bytes = $c->app->report_files->read($rid, 'log_file')
        // return $c->render(status => 404, json => { error => 'Log file not found.' });
    return $c->render(json => { file => $bytes });
}

sub outfile ($c) {
    my $rid = $c->stash('rid');
    my $bytes = $c->app->report_files->read($rid, 'out_file')
        // return $c->render(status => 404, json => { error => 'Out file not found.' });
    return $c->render(json => { file => $bytes });
}
```

`logfile` and `outfile` use the new `Model::ReportFiles` (plan 06) which handles xz decompression and the sharded path lookup based on `report.report_hash`.

Register helpers in `App::startup`:

```perl
$self->helper(reports      => sub ($c) { state $r = CoreSmoke::Model::Reports->new(sqlite => $c->app->sqlite) });
$self->helper(ingest       => sub ($c) { state $i = CoreSmoke::Model::Ingest->new(app => $c->app) });
$self->helper(report_files => sub ($c) { state $f = CoreSmoke::Model::ReportFiles->new(root => $c->app->config->{reports_dir}, sqlite => $c->app->sqlite) });
```

## Search query parameters (preserved from legacy)

The legacy `searchresults` accepts these query params; preserve names and semantics (see `legacy/api/lib/CoreSmokeDB/API/Web.pm` and `ValidationTemplates.pm`):

- `selected_arch`, `selected_osnm`, `selected_osvs`, `selected_host`, `selected_comp`, `selected_cver`, `selected_perl`, `selected_branch`
- `andnotsel_arch`, `andnotsel_osnm`, `andnotsel_osvs`, `andnotsel_host`, `andnotsel_comp`, `andnotsel_cver` (each `0` or `1`)
- `page`, `reports_per_page` (default 25)

`selected_perl` accepts `"all" | "latest" | "<version>"`. `"latest" + no other filters` triggers the per-arch/os/host latest path.

The actual filter compilation lives in `Model::Search` (plan 06).

## CORS

Add a global `after_dispatch` hook in `App::startup`:

```perl
$self->hook(after_dispatch => sub ($c) {
    my $origin = $c->app->config->{cors_allow_origin} // '*';
    $c->res->headers->access_control_allow_origin($origin);
    $c->res->headers->header('Access-Control-Allow-Methods' => 'GET, POST, OPTIONS');
});
```

## OpenAPI spec

Hand-authored at `etc/openapi.yaml` (decision #24). `Controller::Api::openapi_*` actions render this file as JSON or YAML or plain text.

A `t/80-openapi.t` test loads the spec and asserts every documented path is registered in `app->routes`.

## Critical files to read

- `legacy/api/config.yml`  (canonical route map)
- `legacy/api/lib/CoreSmokeDB/API/Web.pm`  (response shapes per method)
- `legacy/api/lib/CoreSmokeDB/API/System.pm`
- `legacy/api/lib/CoreSmokeDB/ValidationTemplates.pm`  (param validation contract)
- `legacy/api/lib/CoreSmokeDB/Client/Database.pm`  (DAO behavior to mirror)

## Verification

1. `script/smoke routes` lists every path in the table above.
2. Fixture-driven tests in `t/30-rest-api.t` (see plan 09) ingest the `idefix-gff5bbe677.jsn` fixture, then assert each GET endpoint produces the expected JSON shape.
3. CORS header is present on every `/api/*` response.
4. `GET /api/openapi/web.json` parses as valid JSON; `web.yaml` parses as valid YAML; the spec lists every actual route.
5. `GET /healthz` returns 200 always; `GET /readyz` returns 200 with a healthy DB and 503 when DB is unreachable.
6. `GET /api/outfile/:rid` works; `GET /api/outfle/:rid` 404s (typo intentionally removed).
