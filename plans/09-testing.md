# 09 — Testing strategy

## Goal

A `Test::Mojo`-based suite that runs in seconds, requires no external services, and pins both REST and JSONRPC parity against the legacy contract. Plus targeted unit tests for the parts with subtle correctness requirements (plevel, ingest dedup + on-disk file roundtrip, search filter compiler).

CI runs the suite on Perl 5.42, runs `perlcritic` at severity 5 (fail on violation, decision #44), and uploads `Devel::Cover` coverage as a report (no enforced threshold, decision #45).

## Test DB layout

**Single shared `t/test.db` reset between tests, sequential runs** (decision #42). `t/lib/TestApp.pm` provides a `reset_db` helper that:

1. Drops and re-runs the migration on `t/test.db`.
2. Removes `t/data/reports-tmp/` recursively.
3. Returns a `Test::Mojo` instance bound to `CoreSmoke::App`.

Tests run sequentially — `prove -lr t/` (no `-j` flag).

## Layout

```
t/
├── 00-load.t                 # all modules compile
├── 01-config.t               # config loads, sqlite path resolves, migrations apply,
│                             #   PRAGMA foreign_keys=1, PRAGMA journal_mode=wal
├── 02-plevel.t               # plevel parity vs hand-curated corpus
├── 10-system.t               # /system/ping, /system/version, /system/status, /system/methods
├── 11-health.t               # /healthz always 200, /readyz reflects DB state
├── 20-api-version.t          # /api/version returns version=2.0, db_version=4
├── 30-rest-api.t             # full REST surface, fixture-driven
├── 40-jsonrpc.t              # JSONRPC parity over the same fixture
├── 41-jsonrpc-errors.t       # transport-level errors and batches
├── 50-ingest.t               # POST /api/report + duplicate detection + xz file on disk
├── 51-ingest-old-format.t    # POST /api/old_format_reports + POST /report alias
├── 52-ingest-gzip.t          # POST /api/report with Content-Encoding: gzip
├── 60-search.t               # filter compiler, AND/NOT, latest perl, paging
├── 61-matrix.t               # matrix shape and counts
├── 62-submatrix.t            # submatrix filtering by test (+ optional pversion)
├── 65-report-files.t         # Model::ReportFiles write/read xz roundtrip
├── 70-web.t                  # server-rendered HTML pages
├── 71-web-htmx.t             # HX-Request returns fragment templates
├── 80-openapi.t              # spec parses; every documented path is mounted
├── 99-cors.t                 # access-control-allow-origin on /api/* responses
├── data/
│   ├── idefix-gff5bbe677.jsn # copied from legacy/api/t/data/
│   ├── plevel-corpus.tsv     # hand-curated, ~30 entries (decision #7)
│   └── reports-tmp/          # ephemeral; cleared by reset_db
└── lib/
    └── TestApp.pm
```

## `t/lib/TestApp.pm`

```perl
package TestApp;
use v5.42;
use experimental qw(signatures);
use Test::Mojo;
use Mojo::File qw(curfile);
use File::Path qw(remove_tree);

my $ROOT = curfile->sibling('..')->to_abs;

sub new ($class) {
    $ENV{MOJO_MODE}         = 'test';
    $ENV{SMOKE_DB_PATH}     = "$ROOT/test.db";
    $ENV{SMOKE_REPORTS_DIR} = "$ROOT/data/reports-tmp";

    reset_db();

    my $t = Test::Mojo->new('CoreSmoke::App');
    return bless { t => $t }, $class;
}

sub reset_db {
    my $db = "$ROOT/test.db";
    unlink $db, "$db-wal", "$db-shm";
    remove_tree("$ROOT/data/reports-tmp");
}

sub t  ($self) { $self->{t} }
sub app($self) { $self->{t}->app }

sub ingest_fixture ($self, $name) {
    my $path = "$ROOT/data/$name";
    my $body = Mojo::JSON::decode_json(Mojo::File->new($path)->slurp);
    return $self->t
        ->post_ok('/api/report', json => { report_data => $body })
        ->status_is(200)
        ->tx->res->json;
}

1;
```

## `t/02-plevel.t` — plevel parity

Hand-curated corpus (no PG dump per decision #7). Each line of `t/data/plevel-corpus.tsv` is `<git_describe>\t<expected_plevel>`. Cover at least:

```
5.42.0                          5.042000zzz000
v5.42.0                         5.042000zzz000
v5.42.0-RC1                     5.042000RC1RC1
v5.42.0-RC2                     5.042000RC2RC2
v5.41.10                        5.041010zzz000
v5.41.10-12-gabc1234            5.041010zzz012
v5.40.2                         5.040002zzz000
v5.40.0-RC3-5-gdef5678          5.040000RC3005
... (~30 total covering release / RC / tagged-with-ahead variants)
```

Outputs are PG-byte-faithful (see `02-database.md` for the `lpad` semantics that produce `RC1RC1` for bare-RC tags).

```perl
use v5.42;
use Test::More;
use Mojo::File qw(curfile);
use CoreSmoke::Model::Plevel;

my $tsv = curfile->sibling('data', 'plevel-corpus.tsv')->slurp;
for my $line (split /\n/, $tsv) {
    next if $line =~ /^\s*(#|$)/;
    my ($describe, $expected) = split /\t/, $line;
    is(CoreSmoke::Model::Plevel::from_git_describe($describe), $expected,
       "plevel($describe) = $expected");
}
done_testing;
```

## `t/30-rest-api.t` — fixture-driven REST surface

```perl
use TestApp;
my $h = TestApp->new;
my $t = $h->t;

$t->get_ok('/api/latest')->status_is(200)
  ->json_has('/reports')->json_is('/report_count' => 0);

my $resp = $h->ingest_fixture('idefix-gff5bbe677.jsn');
my $rid  = $resp->{id};

$t->get_ok('/api/latest')->status_is(200)->json_is('/report_count' => 1);
$t->get_ok("/api/full_report_data/$rid")->status_is(200)->json_has('/sysinfo')->json_has('/configs');
$t->get_ok("/api/report_data/$rid")->status_is(200);
$t->get_ok("/api/logfile/$rid")->status_is(200)->json_has('/file');
$t->get_ok("/api/outfile/$rid")->status_is(200)->json_has('/file');
$t->get_ok("/api/outfle/$rid")->status_is(404);   # legacy typo intentionally removed

$t->get_ok('/api/searchparameters')->status_is(200);
$t->get_ok('/api/searchresults?selected_perl=all')->status_is(200);
$t->get_ok('/api/matrix')->status_is(200);
$t->get_ok('/api/submatrix?test=lib/foo.t')->status_is(200);
$t->get_ok("/api/reports_from_id/$rid")->status_is(200);

# Duplicate detection
$h->t->post_ok('/api/report',
    json => { report_data => Mojo::JSON::decode_json(Mojo::File->new("$ROOT/data/idefix-gff5bbe677.jsn")->slurp) }
)->status_is(409)->json_has('/error');

done_testing;
```

## `t/40-jsonrpc.t` — parity with REST

For each method `M`, fire two requests and assert equal payloads:

```perl
my $rest    = $t->get_ok("/api/$rest_path")->tx->res->json;
my $jsonrpc = $t->post_ok('/api', json => {
    jsonrpc => '2.0', id => 1, method => $M, params => $params
})->tx->res->json->{result};
is_deeply $jsonrpc, $rest, "$M parity";
```

Loop over the table from `04-api-jsonrpc.md`.

## `t/50-ingest.t` + `t/65-report-files.t`

Verify after a successful `POST /api/report`:

1. Response is `{ id => N }`.
2. The `report_hash` column matches `md5_hex(...)` of the unique tuple.
3. The on-disk file `t/data/reports-tmp/<sharded>/log_file.xz` exists.
4. `Model::ReportFiles::read($rid, 'log_file')` returns the original bytes.
5. Re-posting returns 409 `{ error => 'Report already posted.' }`.

`t/65-report-files.t` independently verifies xz round-trip with arbitrary bytes (including utf-8, control chars, large payloads).

## `t/52-ingest-gzip.t`

```perl
use IO::Compress::Gzip qw(gzip);
my $body = Mojo::JSON::encode_json({ report_data => $fixture });
my $gz; gzip(\$body => \$gz);

$t->post_ok('/api/report',
    { 'Content-Encoding' => 'gzip', 'Content-Type' => 'application/json' },
    $gz
)->status_is(200)->json_has('/id');
```

## `t/70-web.t` and `t/71-web-htmx.t`

```perl
$t->get_ok('/')->status_is(200);
$t->get_ok('/search')->status_is(200);
$t->get_ok('/about')->status_is(200);
$t->get_ok('/report/9999')->status_is(404);

# HTMX fragment vs full page
$t->get_ok('/latest', { 'HX-Request' => 'true' })->status_is(200)
  ->content_unlike(qr{<html|<body});           # fragment, not full page
```

## CI outline

`.github/workflows/ci.yml`:

```yaml
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    container:
      image: perl:5.42
    steps:
      - uses: actions/checkout@v4
      - run: cpan -T App::cpm
      - run: cpm install -L local --with-develop
      - name: prove
        run: prove -lr t/                       # sequential per decision #42
      - name: perlcritic
        run: perl -Ilocal/lib/perl5 local/bin/perlcritic --severity 5 lib/
      - name: coverage
        run: |
          PERL5OPT='-MDevel::Cover' prove -lr t/
          perl -Ilocal/lib/perl5 local/bin/cover -report html
      - uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: cover_db/

  docker:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/build-push-action@v5
        with:
          platforms: linux/amd64,linux/arm64
          push: ${{ github.ref == 'refs/heads/main' }}
          tags: ghcr.io/${{ github.repository_owner }}/coresmoke:latest
      - name: trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'ghcr.io/${{ github.repository_owner }}/coresmoke:latest'
          exit-code: '0'                        # report-only per decision #49
          severity: 'HIGH,CRITICAL'
```

## Verification

1. `prove -lr t/` passes locally and in CI.
2. Run time under 30 seconds on a developer laptop.
3. `perlcritic --severity 5 lib/` reports no violations.
4. CI publishes a coverage artifact viewable from the workflow run.
5. New tests are added in tandem with each plan's implementation; no plan is "done" without its tests.
