# 09 — Testing strategy

## Goal

A `Test::Mojo`-based suite that runs in seconds, requires no external services, and pins both REST and JSONRPC parity against the legacy contract. Plus a few targeted unit tests for the parts that have subtle correctness requirements (plevel, ingest dedup, search filter compiler).

## Layout

```
t/
├── 00-load.t                 # all modules compile
├── 01-config.t               # config loads, sqlite path resolves, migrations apply
├── 02-plevel.t               # plevel parity vs legacy
├── 10-system.t               # /system/ping, /system/version, /system/status, /system/methods
├── 20-api-version.t          # /api/version
├── 30-rest-api.t             # full REST surface, fixture-driven
├── 40-jsonrpc.t              # JSONRPC parity over the same fixture
├── 41-jsonrpc-errors.t       # transport-level errors and batches
├── 50-ingest.t               # POST /api/report + duplicate detection
├── 51-ingest-old-format.t    # POST /api/old_format_reports + bytea round-trip
├── 60-search.t               # filter compiler, AND/NOT, latest perl, paging
├── 61-matrix.t               # matrix shape and counts
├── 62-submatrix.t            # submatrix filtering by test (+ optional pversion)
├── 70-web.t                  # server-rendered HTML pages
├── 80-openapi.t              # spec parses; every documented path is mounted
├── 99-cors.t                 # access-control-allow-origin on /api/* responses
├── data/
│   ├── idefix-gff5bbe677.jsn # copied from legacy/api/t/data/
│   └── plevel-corpus.tsv     # one (git_describe, expected_plevel) pair per line
└── lib/
    └── TestApp.pm            # bootstraps a Test::Mojo against a temp smoke.db
```

## `t/lib/TestApp.pm`

```perl
package TestApp;
use v5.42;
use experimental qw(signatures);
use File::Temp ();
use Test::Mojo;
use Mojo::File qw(curfile);

sub new ($class) {
    my $tmp = File::Temp->newdir;
    $ENV{SMOKE_DB_PATH} = "$tmp/smoke.db";
    $ENV{MOJO_MODE}     = 'test';
    my $t = Test::Mojo->new('Perl5::CoreSmoke::App');
    return bless { t => $t, tmp => $tmp }, $class;
}

sub t  ($self) { $self->{t} }
sub app($self) { $self->{t}->app }

sub ingest_fixture ($self, $name) {
    my $path = curfile->sibling('..', 'data', $name);
    my $json = Mojo::File->new($path)->slurp;
    my $body = Mojo::JSON::decode_json($json);
    return $self->t->post_ok('/api/report', json => { report_data => $body })->status_is(200)->tx->res->json;
}

1;
```

Each test gets a fresh empty SQLite DB; tests are independent and can run in parallel.

## `t/02-plevel.t` — parity with the legacy PL/pgSQL function

```perl
use v5.42;
use Test::More;
use Perl5::CoreSmoke::Model::Plevel;

my $tsv = Mojo::File->new("$FindBin::Bin/data/plevel-corpus.tsv")->slurp;
for my $line (split /\n/, $tsv) {
    next if $line =~ /^\s*(#|$)/;
    my ($describe, $expected) = split /\t/, $line;
    is(Perl5::CoreSmoke::Model::Plevel::from_git_describe($describe), $expected,
       "plevel($describe) = $expected");
}
done_testing;
```

`plevel-corpus.tsv` is generated once from a live legacy DB:

```
psql -At -c "SELECT DISTINCT git_describe || E'\t' || plevel FROM report ORDER BY 1" > t/data/plevel-corpus.tsv
```

Even if the user defers full data migration, capturing this corpus is cheap and pins the parity test. If a legacy DB isn't available, hand-author 30+ representative entries (`5.42.0`, `v5.42.0-RC1`, `v5.41.10-12-gabc123`, edge cases with `RC`, etc.).

## `t/30-rest-api.t` — fixture-driven REST surface

```perl
use TestApp;
my $h = TestApp->new;
my $t = $h->t;

# Empty DB sanity
$t->get_ok('/api/latest')->status_is(200)
  ->json_has('/reports')->json_is('/report_count' => 0);

# Ingest the fixture
my $resp = $h->ingest_fixture('idefix-gff5bbe677.jsn');
my $rid  = $resp->{id};

$t->get_ok('/api/latest')->status_is(200)
  ->json_is('/report_count' => 1);

$t->get_ok("/api/full_report_data/$rid")->status_is(200)
  ->json_has('/sysinfo')
  ->json_has('/configs');

$t->get_ok("/api/report_data/$rid")->status_is(200);
$t->get_ok("/api/logfile/$rid")->status_is(200)->json_has('/file');
$t->get_ok("/api/outfle/$rid")->status_is(200)->json_has('/file');     # legacy typo preserved

$t->get_ok('/api/searchparameters')->status_is(200);
$t->get_ok('/api/searchresults?selected_perl=all')->status_is(200);
$t->get_ok('/api/matrix')->status_is(200);
$t->get_ok('/api/submatrix?test=lib/foo.t')->status_is(200);
$t->get_ok("/api/reports_from_id/$rid")->status_is(200);

# Duplicate detection
$h->t->post_ok('/api/report',
    json => { report_data => Mojo::JSON::decode_json(Mojo::File->new("$FindBin::Bin/data/idefix-gff5bbe677.jsn")->slurp) }
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

## `t/41-jsonrpc-errors.t`

- POST malformed JSON → `error.code == -32700`.
- Unknown method → `-32601`.
- Batch request `[ping, version]` → array of two responses, ids preserved.

## `t/60-search.t`

Build 5 reports varying every dimension (architecture, osname, osversion, hostname, perl_id, smoke_branch, cc, ccversion). For each filter combination listed in the legacy `ValidationTemplates.pm`, assert the right subset.

Edge cases:

- `selected_perl=latest` with no other filters → all reports at MAX(plevel).
- `andnotsel_arch=1` flips the equality to inequality.
- `page=2&reports_per_page=2` returns the third pair.

## `t/70-web.t`

```perl
$t->get_ok('/')->status_is(200)->text_is('h1' => 'Latest smoke results');
$t->get_ok('/search')->status_is(200);
$t->get_ok('/about')->status_is(200);
$t->get_ok('/report/9999')->status_is(404);
```

After ingesting the fixture:

```perl
$t->get_ok("/report/$rid")->status_is(200)
  ->text_like('h2' => qr/Smoke report/)
  ->text_like('pre.summary' => qr/PASS|FAIL/);
$t->get_ok("/file/log_file/$rid")->status_is(200)->content_type_like(qr{text/html});
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
      - run: cpm install -L local --no-test
      - run: prove -lr -j4 t/
  docker:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - run: docker build -t coresmoke:ci .
```

## Verification

1. `prove -lr t/` passes locally and in CI.
2. Run time under 10 seconds on a developer laptop (use `prove -j4`).
3. New tests are added in tandem with each plan's implementation; no plan is "done" without its tests.
