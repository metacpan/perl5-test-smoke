use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use TestApp;
use CoreSmoke::Model::Matrix;

my $h  = TestApp->new;
my $db = $h->app->sqlite->db;
my $m  = CoreSmoke::Model::Matrix->new(sqlite => $h->app->sqlite);

# Seed synthetic failure data: 3 failing tests across 1 perl version.
$db->query(q{
    INSERT INTO report (perl_id, plevel, git_id, git_describe, smoke_date,
                        hostname, architecture, osname, osversion, summary,
                        report_hash)
    VALUES ('5.42.0', '5042000', 'abc123', 'v5.42.0-1-gabc',
            '2025-04-25T00:00:00Z', 'testbox', 'x86_64', 'linux', '6.1',
            'FAIL(F)', 'hash_pagination_test')
});
my $rid = $db->query("SELECT last_insert_rowid() AS id")->hash->{id};
$db->query("INSERT INTO config (report_id, arguments, debugging) VALUES (?, '', 'D')", $rid);
my $cid = $db->query("SELECT last_insert_rowid() AS id")->hash->{id};
$db->query("INSERT INTO result (config_id, io_env, summary) VALUES (?, 'stdio', 'F')", $cid);
my $resid = $db->query("SELECT last_insert_rowid() AS id")->hash->{id};

for my $test_name ('t/op/aaa.t', 't/op/bbb.t', 't/op/ccc.t') {
    $db->query("INSERT INTO failure (test, status, extra) VALUES (?, 'FAILED', '')", $test_name);
    my $fid = $db->query("SELECT last_insert_rowid() AS id")->hash->{id};
    $db->query("INSERT INTO failures_for_env (result_id, failure_id) VALUES (?, ?)", $resid, $fid);
}

# --- Unpaginated: returns all 3 rows + counts ---
my $all = $m->matrix;
is scalar @{ $all->{rows} }, 3, 'unpaginated: all 3 tests returned';
is $all->{test_count},    3,    'unpaginated: test_count is 3';
is $all->{hot_failures},  3,    'unpaginated: hot_failures is 3';

# --- Paginated: page 1, 2 per page ---
my $p1 = $m->matrix(page => 1, rows_per_page => 2);
is scalar @{ $p1->{rows} }, 2,  'page 1: 2 rows returned';
is $p1->{test_count},       3,  'page 1: test_count is total 3';
is $p1->{hot_failures},     3,  'page 1: hot_failures is total 3';
ok exists $p1->{rows}[0]{test}, 'page 1: rows have test field';

# --- Paginated: page 2, 2 per page ---
my $p2 = $m->matrix(page => 2, rows_per_page => 2);
is scalar @{ $p2->{rows} }, 1,  'page 2: 1 remaining row';
is $p2->{test_count},       3,  'page 2: test_count still 3';

# --- Paginated: page beyond end ---
my $p3 = $m->matrix(page => 99, rows_per_page => 2);
is scalar @{ $p3->{rows} }, 0,  'page 99: no rows';
is $p3->{test_count},       3,  'page 99: test_count still 3';

# --- Web endpoint: full page ---
my $t = $h->t;
$t->get_ok('/matrix')->status_is(200)
  ->content_like(qr/t\/op\/aaa\.t/,          'matrix page lists a test')
  ->content_like(qr/Showing/,                'matrix page has pagination summary')
  ->element_exists('tbody#matrix-rows',       'matrix table has tbody id');

# --- Web endpoint: HTMX load-more returns fragment ---
$t->get_ok('/matrix?page=1&rows_per_page=2',
    { 'HX-Request' => 'true' }
)->status_is(200)
  ->content_like(qr/hx-load-more/,           'HTMX response has load-more trigger')
  ->content_like(qr/hx-swap-oob/,            'HTMX response has OOB summary');

# --- Web endpoint: last page has no load-more ---
$t->get_ok('/matrix?page=2&rows_per_page=2',
    { 'HX-Request' => 'true' }
)->status_is(200)
  ->content_unlike(qr/hx-load-more/,         'last page has no load-more trigger');

done_testing;
