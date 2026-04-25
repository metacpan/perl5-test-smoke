# 05 — Ingest (`POST /api/report` and `old_format_reports`)

## Goal

Accept Test::Smoke reports from the wire, deduplicate, normalize, compute `plevel`, persist the full report tree (report + configs + results + failures + smoke_config), and return the new id. Preserve both modern (`POST /api/report` JSON body `{report_data: {...}}`) and legacy (`POST /api/old_format_reports` form-urlencoded `json=<percent-encoded JSON>`) intake paths.

## Routes

```
POST /api/report                       Controller::Ingest::post_report
POST /api/old_format_reports           Controller::Ingest::post_old_format_report
```

## Modern path (`POST /api/report`)

Request body: `{ "report_data": <Test::Smoke JSON report> }`.

```perl
sub post_report ($c) {
    my $payload = $c->req->json // return $c->render(status => 400, json => { error => 'Invalid JSON.' });
    my $data    = $payload->{report_data}
        // return $c->render(status => 422, json => { error => 'Missing report_data.' });
    my $result  = $c->app->ingest->post_report($data);
    return $c->render(status => 409, json => $result) if $result->{error};
    return $c->render(json => $result);
}
```

## Legacy path (`POST /api/old_format_reports`)

Old Test::Smoke clients send `application/x-www-form-urlencoded` with one field `json=<percent-encoded JSON>`. They do *not* nest under `report_data`.

```perl
sub post_old_format_report ($c) {
    my $raw = $c->req->param('json')
        // return $c->render(status => 422, json => { error => 'Missing json param.' });
    my $data = eval { Mojo::JSON::decode_json($raw) };
    return $c->render(status => 400, json => { error => "Bad JSON: $@" }) if $@;
    # Old payloads embed bytea fields as decoded UTF-8 strings; re-encode to bytes
    # before they hit BLOB columns. See legacy FreeRoutes.pm.
    Perl5::CoreSmoke::Model::Reports::reencode_bytea($data);
    my $result = $c->app->ingest->post_report($data);
    return $c->render(status => 409, json => $result) if $result->{error};
    return $c->render(json => $result);
}
```

## DAO: `Model::Ingest`

(Lives in `lib/Perl5/CoreSmoke/Model/Ingest.pm`; helper `ingest` registered in `App::startup`.)

`post_report($data)` responsibilities:

1. **Lowercase top-level keys** (legacy contract — `Database.pm::post_report`).
2. **Smoke config dedup** — `Digest::MD5::md5_hex` over the canonical-sorted `_config` JSON; `find_or_create` on `smoke_config(md5)`. Use a single `INSERT ... ON CONFLICT(md5) DO NOTHING; SELECT id` round trip.
3. **Array → newline-joined strings** for fields `qw(skipped_tests applied_patches compiler_msgs manifest_msgs nonfatal_msgs)`.
4. **Timestamps** — convert `smoke_date` and `started` from whatever form Test::Smoke supplies (epoch, ISO, RFC 3339) to ISO 8601 UTC TEXT (`YYYY-MM-DDTHH:MM:SSZ`).
5. **Compute plevel** via `Perl5::CoreSmoke::Model::Plevel::from_git_describe($data->{git_describe})`.
6. **Insert** in a single transaction:
   - `report` row (with `sconfig_id`, `plevel`, all flat fields).
   - For each `configs[]`: insert `config` (FK report_id), then for each `results[]` insert `result` (FK config_id), then for each `failures[]` `find_or_create` `failure(test, status, extra)` and `INSERT OR IGNORE` into `failures_for_env`.
7. **Duplicate handling**: catch `UNIQUE constraint failed` errors on `report` (the composite key `git_id, smoke_date, duration, hostname, architecture`). Return `{ error => 'Report already posted.', db_error => "$err" }` and HTTP 409 — matching the legacy text exactly so existing clients can detect it.
8. **Success**: return `{ id => $report_id }`.

```perl
sub post_report ($self, $raw) {
    my $data = $self->_normalize($raw);
    my $sconfig_id = $self->_upsert_smoke_config(delete $data->{_config});

    my $tx = $self->sqlite->db->begin;
    my $rid = eval {
        my $id = $self->_insert_report($data, $sconfig_id);
        for my $cfg (@{ $data->{configs} // [] }) {
            my $cid = $self->_insert_config($id, $cfg);
            for my $res (@{ $cfg->{results} // [] }) {
                my $resid = $self->_insert_result($cid, $res);
                $self->_insert_failures($resid, $res->{failures} // []);
            }
        }
        $id;
    };
    if (my $e = $@) {
        return { error => 'Report already posted.', db_error => "$e" }
            if $e =~ /UNIQUE constraint failed/i;
        die $e;
    }
    $tx->commit;
    return { id => $rid };
}
```

## BLOB encoding caveat

Legacy bytea fields (`compiler_msgs`, `manifest_msgs`, `nonfatal_msgs`, `log_file`, `out_file`) are stored as bytes. Test::Smoke sends them as JSON strings (UTF-8 text). On insert, encode to UTF-8 bytes before binding so SQLite stores them as BLOB consistently:

```perl
sub _bytea ($v) {
    return undef unless defined $v;
    return Encode::encode('utf-8', $v);
}
```

## Routes

In `App::startup`:

```perl
$r->post('/api/report')->to('Ingest#post_report');
$r->post('/api/old_format_reports')->to('Ingest#post_old_format_report');
```

Legacy route at `POST /report` (no `/api`) was Fastly-redirected to `/api/old_format_reports`. We don't ship Fastly; document that operations should configure their proxy to do the same redirect, or add a Mojolicious route as a convenience:

```perl
$r->post('/report')->to('Ingest#post_old_format_report');  # legacy convenience
```

## Critical files to read

- `legacy/api/lib/Perl5/CoreSmokeDB/Client/Database.pm`  (`post_report`, `post_smoke_config`, the data normalization rules)
- `legacy/api/lib/Perl5/CoreSmokeDB/API/Web.pm`         (`rpc_post_report`)
- `legacy/api/lib/Perl5/CoreSmokeDB/API/FreeRoutes.pm`  (legacy `/report` endpoint behavior)
- `legacy/api/t/data/idefix-gff5bbe677.jsn`             (canonical fixture)
- `legacy/api/t/150-post-report.t`                      (duplicate-detection assertions to mirror)

## Verification

1. `t/50-ingest.t` posts the fixture to `POST /api/report`, asserts response `{ id => N }`, then re-posts and asserts `{ error => 'Report already posted.', db_error => qr/UNIQUE constraint failed/ }` with HTTP 409.
2. The same fixture, percent-encoded into a `json=` form post, succeeds at `POST /api/old_format_reports`.
3. After ingest, `GET /api/full_report_data/$id` returns the same shape as the legacy stack does for the same fixture (compared via `Test::Deep`).
4. `smoke_config` dedup: post the fixture; post a *different* report that re-uses the same `_config` block; assert only one `smoke_config` row exists and both reports reference it.
5. `plevel` is populated and matches `Model::Plevel::from_git_describe($data->{git_describe})`.
