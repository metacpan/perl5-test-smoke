use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use Mojo::Util qw(url_escape);
use TestApp;

my $h = TestApp->new;
my $t = $h->t;

my $resp = $h->ingest_fixture('idefix-gff5bbe677.jsn');
ok $resp->{id}, "ingested report $resp->{id}";

# Baseline: DB is queryable.
$t->get_ok('/api/searchresults')
  ->status_is(200)
  ->json_is('/report_count' => 1, 'baseline: report table intact');

# --- SQL injection payloads in text filters ---

$t->get_ok('/api/searchresults?selected_host=' . url_escape("'; DROP TABLE report; --"))
  ->status_is(200)
  ->json_is('/report_count' => 0, 'sqli in hostname: no match, no crash');

$t->get_ok('/api/searchresults?selected_arch=' . url_escape("x86 OR 1=1"))
  ->status_is(200)
  ->json_is('/report_count' => 0, 'tautology in arch: no match');

$t->get_ok('/api/searchresults?selected_osnm=' . url_escape("linux' UNION SELECT sql FROM sqlite_master--"))
  ->status_is(200)
  ->json_is('/report_count' => 0, 'UNION injection in osname: no match');

# --- Injection in summary filter (uses GLOB pattern) ---

$t->get_ok('/api/searchresults?selected_summary=' . url_escape("PASS'; DELETE FROM report; --"))
  ->status_is(200);

# --- Injection in date filters (date range uses date() function) ---

$t->get_ok('/api/searchresults?date_from=' . url_escape("2024-01-01'; DROP TABLE report; --"))
  ->status_is(200);

$t->get_ok('/api/searchresults?date_to=' . url_escape("2024-01-01' OR '1'='1"))
  ->status_is(200);

# --- Injection in config join filters ---

$t->get_ok('/api/searchresults?selected_comp=' . url_escape("gcc'; DROP TABLE config; --"))
  ->status_is(200)
  ->json_is('/report_count' => 0, 'sqli in compiler: no match');

# --- Injection in perl_id filter ---

$t->get_ok('/api/searchresults?selected_perl=' . url_escape("1 OR 1=1"))
  ->status_is(200)
  ->json_is('/report_count' => 0, 'tautology in perl_id: no match');

# --- Injection via POST (form-encoded) ---

$t->post_ok('/api/searchresults' => form => {
    selected_host => "'; DROP TABLE report; --",
    selected_arch => "x86' OR '1'='1",
  })
  ->status_is(200)
  ->json_is('/report_count' => 0, 'sqli via POST form: no match');

# --- Verify DB survived all injection attempts ---

$t->get_ok('/api/searchresults')
  ->status_is(200)
  ->json_is('/report_count' => 1, 'report table intact after all injections');

my $db = $h->app->sqlite->db;
my $count = $db->query("SELECT COUNT(*) AS n FROM report")->hash->{n};
is $count, 1, 'direct DB query confirms report row survived';

done_testing;
