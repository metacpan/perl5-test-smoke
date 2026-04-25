# 05 — Ingest (`POST /api/report`, `old_format_reports`, `/report`)

## Goal

Accept Test::Smoke reports, normalize, deduplicate, compute `plevel`, **write the five legacy bytea fields to disk as xz files**, and INSERT the report tree (report + configs + results + failures + smoke_config). Three intake paths must work:

1. `POST /api/report` — modern Test::Smoke (JSON body `{report_data: {...}}`); honor `Content-Encoding: gzip` (decision #28).
2. `POST /api/old_format_reports` — pre-1.81 Test::Smoke clients (form-urlencoded `json=<percent-encoded JSON>`).
3. `POST /report` — built-in alias for the legacy Fastly redirect target (decision #10, **required** in 2.0).

## Routes

```perl
# In App::startup
$r->post('/api/report')              ->to('Ingest#post_report');
$r->post('/api/old_format_reports')  ->to('Ingest#post_old_format_report');
$r->post('/report')                  ->to('Ingest#post_old_format_report');   # legacy alias
```

## gzip request body handling

Mojolicious doesn't decompress request bodies by default. Add a `before_dispatch` hook in `App::startup`:

```perl
$self->hook(before_dispatch => sub ($c) {
    my $enc = $c->req->headers->header('Content-Encoding') // '';
    return unless $enc eq 'gzip';

    require IO::Uncompress::Gunzip;
    my $body = $c->req->body;
    my $out  = '';
    IO::Uncompress::Gunzip::gunzip(\$body => \$out)
        or return $c->render(status => 400, json => { error => 'Bad gzip body' });
    $c->req->body($out);
    $c->req->headers->remove('Content-Encoding');
});
```

This sits in front of every route, so any endpoint can transparently accept gzip if a client wants to send it.

## Modern path: `POST /api/report`

```perl
sub post_report ($c) {
    my $payload = $c->req->json
        // return $c->render(status => 400, json => { error => 'Invalid JSON.' });
    my $data = $payload->{report_data}
        // return $c->render(status => 422, json => { error => 'Missing report_data.' });
    my $result = $c->app->ingest->post_report($data);
    return $c->render(status => 409, json => $result) if $result->{error};
    return $c->render(json => $result);
}
```

## Legacy path: `POST /api/old_format_reports` and `POST /report`

```perl
sub post_old_format_report ($c) {
    my $raw = $c->req->param('json')
        // return $c->render(status => 422, json => { error => 'Missing json param.' });
    my $data = eval { Mojo::JSON::decode_json($raw) };
    return $c->render(status => 400, json => { error => "Bad JSON: $@" }) if $@;
    my $result = $c->app->ingest->post_report($data);
    return $c->render(status => 409, json => $result) if $result->{error};
    return $c->render(json => $result);
}
```

(The legacy "re-encode bytea fields to UTF-8 bytes before SQLite stores them as BLOB" step is gone — there are no BLOB columns now. UTF-8 bytes go straight to disk via `Model::ReportFiles`.)

## DAO: `Model::Ingest`

(Lives in `lib/CoreSmoke/Model/Ingest.pm`; helper `ingest` registered in `App::startup`.)

`post_report($data)` responsibilities:

1. **Lowercase top-level keys** (legacy contract).
2. **Smoke config dedup** — `Digest::MD5::md5_hex` over the canonical-sorted `_config` JSON; `find_or_create` on `smoke_config(md5)`. Single `INSERT ... ON CONFLICT(md5) DO NOTHING; SELECT id` round trip.
3. **Array → newline-joined strings** for fields `qw(skipped_tests applied_patches)` (these stay in the DB as TEXT).
4. **Extract on-disk fields** — pop `log_file`, `out_file`, `manifest_msgs`, `compiler_msgs`, `nonfatal_msgs` out of `$data`. They never touch the `report` table.
5. **Timestamps** — convert `smoke_date` and `started` to ISO 8601 UTC TEXT (`YYYY-MM-DDTHH:MM:SSZ`).
6. **Compute plevel** via `CoreSmoke::Model::Plevel::from_git_describe($data->{git_describe})`.
7. **Compute report_hash** via `app->sqlite->report_hash($data)` = `md5_hex(join "\0", git_id, smoke_date, duration, hostname, architecture)`.
8. **Write files first** under `data/reports/<h0..1>/<h2..3>/<h4..5>/<full-hash>/` (decision #31). Each non-empty field is xz-compressed (decision #32) to `<field>.xz`. Best-effort: log and continue on write failure (decision #33).
9. **Insert** in a single transaction:
   - `report` row (with `sconfig_id`, `plevel`, `report_hash`, all flat fields).
   - For each `configs[]`: insert `config` (FK report_id), then for each `results[]` insert `result` (FK config_id), then for each `failures[]` `find_or_create` `failure(test, status, extra)` and `INSERT OR IGNORE` into `failures_for_env`.
10. **Duplicate handling**: catch `UNIQUE constraint failed` errors. Return `{ error => 'Report already posted.', db_error => "$err" }` and HTTP 409. Files are already on disk under the same hash — that's fine, it's the same content.
11. **Success**: return `{ id => $report_id }`.

```perl
package CoreSmoke::Model::Ingest;
use v5.42;
use experimental qw(signatures);

sub post_report ($self, $raw) {
    my $data       = $self->_normalize($raw);
    my $hash       = $self->{sqlite}->report_hash($data);
    my $files      = {
        map { my $v = delete $data->{$_}; defined $v ? ($_ => $v) : () }
        qw(log_file out_file manifest_msgs compiler_msgs nonfatal_msgs)
    };

    # Write files BEFORE the row (decision #33).
    $self->{report_files}->write($hash, $files);

    my $sconfig_id = $self->_upsert_smoke_config(delete $data->{_config});
    $data->{plevel}      = CoreSmoke::Model::Plevel::from_git_describe($data->{git_describe});
    $data->{report_hash} = $hash;
    $data->{sconfig_id}  = $sconfig_id;

    my $tx = $self->{sqlite}->db->begin;
    my $rid = eval {
        my $id = $self->_insert_report($data);
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

## On-disk file path

`Model::ReportFiles::path_for($hash)` (plan 06) returns `data/reports/<h[0..1]>/<h[2..3]>/<h[4..5]>/<full-hash>/`. Example:

```
report_hash = "ab12cd34ef56..."
path        = data/reports/ab/12/cd/ab12cd34ef56.../
files       = log_file.xz, out_file.xz, manifest_msgs.xz, compiler_msgs.xz, nonfatal_msgs.xz
```

## Critical files to read

- `legacy/api/lib/CoreSmokeDB/Client/Database.pm`  (`post_report`, `post_smoke_config`, the data normalization rules)
- `legacy/api/lib/CoreSmokeDB/API/Web.pm`         (`rpc_post_report`)
- `legacy/api/lib/CoreSmokeDB/API/FreeRoutes.pm`  (legacy `/report` endpoint behavior)
- `legacy/api/t/data/idefix-gff5bbe677.jsn`       (canonical fixture)
- `legacy/api/t/150-post-report.t`                (duplicate-detection assertions to mirror)

## Verification

1. `t/50-ingest.t` posts the fixture to `POST /api/report`, asserts response `{ id => N }`, then re-posts and asserts `{ error => 'Report already posted.', db_error => qr/UNIQUE constraint failed/ }` with HTTP 409.
2. After a successful post, `data/reports/<h[0..1]>/<h[2..3]>/<h[4..5]>/<hash>/log_file.xz` exists and decompresses to the original content.
3. After a successful post, the `report` table has **no** BLOB columns populated (they don't exist) and `report_hash` matches the on-disk dir name.
4. `t/51-ingest-old-format.t` posts the same fixture percent-encoded into `json=` form to `POST /api/old_format_reports` and to `POST /report`; both succeed.
5. `POST /api/report` with `Content-Encoding: gzip` and a gzipped body succeeds.
6. `smoke_config` dedup: post the fixture; post a different report that re-uses the same `_config` block; assert only one `smoke_config` row exists.
7. `plevel` is populated and matches `Model::Plevel::from_git_describe($data->{git_describe})`.
