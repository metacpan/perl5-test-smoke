use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use TestApp;

my $h  = TestApp->new;
my $t  = $h->t;
my $db = $h->app->sqlite->db;

# =========================================================================
# 1. Ingest the FAIL fixture via POST /api/report
# =========================================================================

my $resp = $h->ingest_fixture('fail-report.jsn');
ok $resp->{id}, "FAIL fixture ingested (id=$resp->{id})";
my $rid = $resp->{id};

# =========================================================================
# 2. Verify report row in DB
# =========================================================================

my $row = $db->query(
    "SELECT summary, hostname, plevel, report_hash FROM report WHERE id = ?",
    $rid,
)->hash;
is $row->{summary},  'FAIL(F)', 'summary stored as FAIL(F)';
is $row->{hostname}, 'smokebox', 'hostname flattened from sysinfo';
like $row->{plevel}, qr/^5\./, 'plevel computed';
like $row->{report_hash}, qr/^[a-f0-9]{32}$/, 'report_hash is md5';

# =========================================================================
# 3. Verify configs: 2 configs (non-debug + debug)
# =========================================================================

my $configs = $db->query(
    "SELECT * FROM config WHERE report_id = ? ORDER BY id", $rid,
)->hashes->to_array;
is scalar @$configs, 2, 'two configs inserted';
is $configs->[0]{debugging}, 'N', 'first config: non-debug';
is $configs->[1]{debugging}, 'D', 'second config: debug';
is $configs->[1]{arguments}, '-DDEBUGGING', 'debug config has arguments';

# =========================================================================
# 4. Verify results: 6 total (3 io_envs x 2 configs)
# =========================================================================

my $results = $db->query(<<~'SQL', $rid)->hashes->to_array;
    SELECT r.* FROM result r
      JOIN config c ON c.id = r.config_id
     WHERE c.report_id = ?
     ORDER BY c.id, r.id
    SQL
is scalar @$results, 6, 'six results (3 io_envs x 2 configs)';

my @failing = grep { $_->{summary} eq 'F' } @$results;
is scalar @failing, 2, 'two failing results (perlio + locale in first config)';

my @passing = grep { $_->{summary} eq 'O' } @$results;
is scalar @passing, 4, 'four passing results';

# =========================================================================
# 5. Verify failures inserted end-to-end via _insert_failures
# =========================================================================

my $failures = $db->query(<<~'SQL', $rid)->hashes->to_array;
    SELECT DISTINCT f.test, f.status, f.extra
      FROM failure f
      JOIN failures_for_env ffe ON ffe.failure_id = f.id
      JOIN result rs ON rs.id = ffe.result_id
      JOIN config c  ON c.id  = rs.config_id
     WHERE c.report_id = ?
     ORDER BY f.test
    SQL
is scalar @$failures, 2, 'two distinct failures (op/magic.t + op/taint.t)';
is $failures->[0]{test}, 'op/magic.t',  'first failure: op/magic.t';
is $failures->[0]{status}, 'FAILED', 'failure status';
like $failures->[0]{extra}, qr/Failed test at op\/magic\.t/,
    'failure extra contains detail text';
is $failures->[1]{test}, 'op/taint.t', 'second failure: op/taint.t';

# op/magic.t appears in both perlio and locale results -> 2 links
my $magic_links = $db->query(<<~'SQL', $rid)->hash->{c};
    SELECT COUNT(*) AS c
      FROM failures_for_env ffe
      JOIN result rs ON rs.id = ffe.result_id
      JOIN config c  ON c.id  = rs.config_id
      JOIN failure f ON f.id  = ffe.failure_id
     WHERE c.report_id = ? AND f.test = 'op/magic.t'
    SQL
is $magic_links, 2, 'op/magic.t linked to 2 results (perlio + locale)';

# op/taint.t appears only in perlio -> 1 link
my $taint_links = $db->query(<<~'SQL', $rid)->hash->{c};
    SELECT COUNT(*) AS c
      FROM failures_for_env ffe
      JOIN result rs ON rs.id = ffe.result_id
      JOIN config c  ON c.id  = rs.config_id
      JOIN failure f ON f.id  = ffe.failure_id
     WHERE c.report_id = ? AND f.test = 'op/taint.t'
    SQL
is $taint_links, 1, 'op/taint.t linked to 1 result (perlio only)';

# =========================================================================
# 6. Verify /api/full_report_data structure
# =========================================================================

my $full = $t->get_ok("/api/full_report_data/$rid")->status_is(200)
  ->json_has('/test_failures')
  ->json_has('/matrix_rows')
  ->json_has('/c_compilers')
  ->json_has('/compiler_msgs_text')
  ->tx->res->json;

is scalar @{ $full->{test_failures} }, 2,
    'full_report_data: two test_failures entries';

my ($magic_f) = grep { $_->{test} eq 'op/magic.t' } @{ $full->{test_failures} };
ok $magic_f, 'op/magic.t in test_failures';
is $magic_f->{status}, 'FAILED', 'failure status in report data';
is scalar @{ $magic_f->{configs} }, 2,
    'op/magic.t failed in 2 config+env combos (perlio + locale)';

my ($taint_f) = grep { $_->{test} eq 'op/taint.t' } @{ $full->{test_failures} };
ok $taint_f, 'op/taint.t in test_failures';
is scalar @{ $taint_f->{configs} }, 1,
    'op/taint.t failed in 1 config+env combo (perlio only)';

# Matrix rows: 2 configs -> 2 matrix rows
is scalar @{ $full->{matrix_rows} }, 2, 'two matrix rows';

# Compiler messages round-tripped through disk
like $full->{compiler_msgs_text}, qr/unused variable/,
    'compiler_msgs_text includes compiler warning';

# On-disk log_file and out_file present (fixture has non-empty values)
ok $full->{has_log_file}, 'has_log_file is true';
ok $full->{has_out_file}, 'has_out_file is true';

# =========================================================================
# 7. GET /report/:rid -- web page renders failure details
# =========================================================================

$t->get_ok("/report/$rid")->status_is(200)
  ->text_like('h1' => qr/Smoke report #\Q$rid\E/)
  ->content_like(qr/op\/magic\.t/, 'failure test name in report page')
  ->content_like(qr/op\/taint\.t/, 'second failure in report page')
  ->content_like(qr/FAILED/, 'failure status rendered')
  ->content_like(qr/FAIL\(F\)/, 'FAIL(F) summary on report page');

# =========================================================================
# 8. GET /latest -- FAIL report appears with correct status
# =========================================================================

$t->get_ok('/latest')->status_is(200)
  ->content_like(qr/smokebox/, 'FAIL report hostname on /latest');

$t->get_ok('/latest?selected_summary=fail')->status_is(200)
  ->content_like(qr/smokebox/, 'fail filter includes FAIL report');

$t->get_ok('/latest?selected_summary=pass')->status_is(200)
  ->content_unlike(qr/smokebox/, 'pass filter excludes FAIL report');

# =========================================================================
# 9. GET /search -- FAIL report findable by summary filter
# =========================================================================

$t->get_ok('/search?selected_summary=FAIL(*)')->status_is(200)
  ->content_like(qr/smokebox/, 'search FAIL(*) finds the report');

$t->get_ok('/search?selected_summary=FAIL(F)')->status_is(200)
  ->content_like(qr/smokebox/, 'search FAIL(F) finds the report');

$t->get_ok('/search?selected_summary=PASS')->status_is(200)
  ->content_unlike(qr/smokebox/, 'search PASS excludes FAIL report');

# JSONRPC searchresults parity
my $rpc_fail = $t->post_ok('/api', json => {
    jsonrpc => '2.0', id => 1,
    method  => 'searchresults',
    params  => { selected_summary => 'FAIL(*)' },
})->status_is(200)->tx->res->json;
ok $rpc_fail->{result}{report_count} >= 1,
    'JSONRPC FAIL(*) filter finds the report';

my $rpc_f = $t->post_ok('/api', json => {
    jsonrpc => '2.0', id => 2,
    method  => 'searchresults',
    params  => { selected_summary => 'FAIL(F)' },
})->status_is(200)->tx->res->json;
ok $rpc_f->{result}{report_count} >= 1,
    'JSONRPC FAIL(F) filter finds the report';

# =========================================================================
# 10. GET /matrix -- failure appears in the matrix
# =========================================================================

$t->get_ok('/matrix')->status_is(200)
  ->content_like(qr/op\/magic\.t/, 'op/magic.t in matrix page');

# Verify on-disk file routes work for this report
$t->get_ok("/file/log_file/$rid")->status_is(200)
  ->content_like(qr/Build log line/, 'log_file content accessible');
$t->get_ok("/file/out_file/$rid")->status_is(200)
  ->content_like(qr/Output line/, 'out_file content accessible');

# API file endpoints
$t->get_ok("/api/logfile/$rid")->status_is(200);
$t->get_ok("/api/outfile/$rid")->status_is(200);

done_testing;
