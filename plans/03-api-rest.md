# 03 — REST API controllers

## Goal

Re-expose every legacy `/api/*` and `/system/*` REST path with byte-compatible request/response shapes, served by `Controller::Api`, `Controller::System`, and `Controller::Ingest`.

## Route map (from `legacy/api/config.yml`)

### `Controller::System` (`/system`)

| Verb | Path | DAO method | Notes |
|------|------|-----------|-------|
| GET | `/system/ping` | `ping` | returns `"pong"` plain |
| GET | `/system/version` | `version` | `{software_version}` |
| GET | `/system/status` | `status` | `{app_version, app_name, active_since, hostname, running_pid, dancer2 (now mojolicious), rpc_plugin}` — keep keys for compat; switch `dancer2` value to actual Mojolicious version, leave key name |
| GET | `/system/methods` | `list_methods` | full method list |
| GET | `/system/methods/:plugin` | `list_methods` | filtered by plugin name |

### `Controller::Api` (`/api`)

| Verb | Path | DAO method (`Model::Reports`) | Notes |
|------|------|-------------------------------|-------|
| GET | `/api/version` | `version` | `{version, schema_version, db_version}` |
| GET | `/api/latest` | `latest` | `{reports[], report_count, latest_plevel, rpp, page}` |
| GET | `/api/full_report_data/:rid` | `full_report_data` | full expanded report; 404 on miss |
| GET | `/api/report_data/:rid` | `report_data` | report+linked data hashref; 404 on miss |
| GET | `/api/logfile/:rid` | `logfile` | `{file: <log_file>}` (deprecated; preserved) |
| GET | `/api/outfle/:rid` | `outfile` | `{file: <out_file>}` — **typo `outfle` is intentional and preserved** |
| GET | `/api/matrix` | `matrix` | failure matrix |
| GET | `/api/submatrix` | `submatrix` | params `test` (req), `pversion` (opt) |
| GET | `/api/searchparameters` | `searchparameters` | filter dropdown source |
| GET, POST | `/api/searchresults` | `searchresults` | full filter set + paging |
| GET | `/api/reports_from_id/:rid` | `reports_from_id` | optional `?limit=N` (default 100) |
| GET | `/api/reports_from_date/:epoch` | `reports_from_epoch` | |
| POST | `/api/report` | `post_report` | covered in plan 05 |
| POST | `/api/old_format_reports` | `post_report` (legacy adapter) | covered in plan 05 |
| GET | `/api/openapi/web.json` | n/a | spec, served as JSON |
| GET | `/api/openapi/web.yaml` | n/a | spec, served as YAML |
| GET | `/api/openapi/web` | n/a | spec, served as `text/plain` |

## Controller pattern

```perl
package Perl5::CoreSmoke::Controller::Api;
use v5.42;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub latest ($c) {
    my $data = $c->app->reports->latest;
    return $c->render(json => $data);
}

sub full_report_data ($c) {
    my $rid  = $c->stash('rid');
    my $data = $c->app->reports->full_report_data($rid)
        // return $c->render(status => 404, json => { error => 'Report not found.' });
    return $c->render(json => $data);
}

# ...
```

Register a `reports` helper in `App::startup`:

```perl
$self->helper(reports => sub ($c) {
    state $r = Perl5::CoreSmoke::Model::Reports->new(sqlite => $c->app->sqlite);
});
```

## Search query parameters (preserved from legacy)

The legacy `searchresults` accepts these query params; preserve names and semantics (see `legacy/api/lib/Perl5/CoreSmokeDB/API/Web.pm` and `ValidationTemplates.pm`):

- `selected_arch`, `selected_osnm`, `selected_osvs`, `selected_host`, `selected_comp`, `selected_cver`, `selected_perl`, `selected_branch`
- `andnotsel_arch`, `andnotsel_osnm`, `andnotsel_osvs`, `andnotsel_host`, `andnotsel_comp`, `andnotsel_cver` (each `0` or `1`)
- `page`, `reports_per_page`

`selected_perl` accepts `"all" | "latest" | "<version>"`. `"latest" + no other filters` triggers the per-arch/os/host latest path.

The actual filter compilation lives in `Model::Search` (plan 06).

## CORS

Re-enable CORS to match legacy behavior. Add a global `before_dispatch` hook in `App::startup`:

```perl
$self->hook(after_dispatch => sub ($c) {
    my $origin = $c->app->config->{cors_allow_origin} // '*';
    $c->res->headers->access_control_allow_origin($origin);
    $c->res->headers->header('Access-Control-Allow-Methods' => 'GET, POST, OPTIONS');
});
```

## OpenAPI spec

The legacy app generates the OpenAPI document at startup from its route metadata. For 2.0:

1. Maintain a single `etc/openapi.yaml` source of truth, hand-authored from the route map above.
2. Ship `Controller::Api::openapi_*` actions that render this file as JSON or YAML.
3. Run a `t/05-openapi.t` test that loads the spec and asserts every documented path is registered in `app->routes`.

## Critical files to read

- `legacy/api/config.yml`  (canonical route map)
- `legacy/api/lib/Perl5/CoreSmokeDB/API/Web.pm`  (response shapes per method)
- `legacy/api/lib/Perl5/CoreSmokeDB/API/System.pm`
- `legacy/api/lib/Perl5/CoreSmokeDB/ValidationTemplates.pm`  (param validation contract)
- `legacy/api/lib/Perl5/CoreSmokeDB/Client/Database.pm`  (DAO behavior to mirror)

## Verification

1. `script/smoke routes` lists every path in the table above.
2. Fixture-driven tests in `t/30-rest-api.t` (see plan 09) ingest the `idefix-gff5bbe677.jsn` fixture, then assert each GET endpoint produces the expected JSON shape.
3. CORS header is present on every `/api/*` response.
4. `GET /api/openapi/web.json` parses as valid JSON; `web.yaml` parses as valid YAML; the spec lists every actual route.
