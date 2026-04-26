use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use TestApp;

my $h = TestApp->new;
my $t = $h->t;

# --- JSONRPC post_report ---------------------------------------------------

subtest 'post_report via JSONRPC' => sub {
    my $fixture = $h->fixture('idefix-gff5bbe677.jsn');

    my $res = $t->post_ok('/api', json => {
        jsonrpc => '2.0', id => 1,
        method  => 'post_report',
        params  => { report_data => $fixture },
    })->status_is(200)
      ->json_is('/jsonrpc' => '2.0')
      ->json_is('/id'      => 1)
      ->json_has('/result/id')
      ->tx->res->json;

    my $rid = $res->{result}{id};
    ok $rid, "ingested report via JSONRPC (id=$rid)";

    my $row = $h->app->sqlite->db->query(
        "SELECT hostname, summary FROM report WHERE id = ?", $rid
    )->hash;
    is $row->{hostname}, 'idefix', 'hostname stored correctly';
    is $row->{summary},  'PASS',   'summary stored correctly';
};

subtest 'post_report duplicate via JSONRPC' => sub {
    my $res = $t->post_ok('/api', json => {
        jsonrpc => '2.0', id => 2,
        method  => 'post_report',
        params  => { report_data => $h->fixture('idefix-gff5bbe677.jsn') },
    })->status_is(200)->tx->res->json;

    ok $res->{result}{error}, 'duplicate returns application-level error in result';
    like $res->{result}{error}, qr/already posted/i, 'error mentions duplicate';
};

# --- JSONRPC searchresults with filters ------------------------------------

subtest 'searchresults with hostname filter' => sub {
    my $res = $t->post_ok('/api', json => {
        jsonrpc => '2.0', id => 3,
        method  => 'searchresults',
        params  => { selected_host => 'idefix' },
    })->status_is(200)
      ->json_is('/jsonrpc' => '2.0')
      ->json_is('/id'      => 3)
      ->tx->res->json;

    is $res->{result}{report_count}, 1, 'hostname filter: found 1 report';
    is $res->{result}{reports}[0]{hostname}, 'idefix',
       'returned report has correct hostname';
};

subtest 'searchresults with non-matching hostname' => sub {
    $t->post_ok('/api', json => {
        jsonrpc => '2.0', id => 4,
        method  => 'searchresults',
        params  => { selected_host => 'nonexistent' },
    })->status_is(200)
      ->json_is('/result/report_count' => 0)
      ->json_is('/result/reports'      => []);
};

subtest 'searchresults with summary filter' => sub {
    $t->post_ok('/api', json => {
        jsonrpc => '2.0', id => 5,
        method  => 'searchresults',
        params  => { selected_summary => 'PASS' },
    })->status_is(200)
      ->json_is('/result/report_count' => 1, 'PASS filter matches');

    $t->post_ok('/api', json => {
        jsonrpc => '2.0', id => 6,
        method  => 'searchresults',
        params  => { selected_summary => 'FAIL(*)' },
    })->status_is(200)
      ->json_is('/result/report_count' => 0, 'FAIL filter excludes');
};

subtest 'searchresults with date filter' => sub {
    $t->post_ok('/api', json => {
        jsonrpc => '2.0', id => 7,
        method  => 'searchresults',
        params  => { date_from => '2022-07-01' },
    })->status_is(200)
      ->json_is('/result/report_count' => 1, 'date_from before smoke_date: included');

    $t->post_ok('/api', json => {
        jsonrpc => '2.0', id => 8,
        method  => 'searchresults',
        params  => { date_from => '2023-01-01' },
    })->status_is(200)
      ->json_is('/result/report_count' => 0, 'date_from after smoke_date: excluded');
};

subtest 'searchresults REST/JSONRPC parity with filters' => sub {
    my $rest = $t->get_ok('/api/searchresults?selected_host=idefix')
        ->status_is(200)->tx->res->json;

    my $rpc = $t->post_ok('/api', json => {
        jsonrpc => '2.0', id => 9,
        method  => 'searchresults',
        params  => { selected_host => 'idefix' },
    })->status_is(200)->tx->res->json->{result};

    is_deeply $rpc, $rest, 'filtered searchresults: REST/JSONRPC parity';
};

done_testing;
