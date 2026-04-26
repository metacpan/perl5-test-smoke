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

# Ingest a fixture so there's data to filter against.
my $resp = $h->ingest_fixture('idefix-gff5bbe677.jsn');
ok $resp->{id}, "ingested report $resp->{id}";

# Baseline: unfiltered search sees the report.
$t->get_ok('/api/searchresults')
  ->status_is(200)
  ->json_is('/report_count' => 1, 'unfiltered: 1 report');

# --- date_from filter (was missing from the API controller) ---

# The fixture's smoke_date is 2022-07-31.  date_from=2022-07-01
# should include it; date_from=2023-01-01 should exclude it.
$t->get_ok('/api/searchresults?date_from=2022-07-01')
  ->status_is(200)
  ->json_is('/report_count' => 1, 'date_from before smoke_date: included');

$t->get_ok('/api/searchresults?date_from=2023-01-01')
  ->status_is(200)
  ->json_is('/report_count' => 0, 'date_from after smoke_date: excluded');

# --- date_to filter ---

$t->get_ok('/api/searchresults?date_to=2022-07-31')
  ->status_is(200)
  ->json_is('/report_count' => 1, 'date_to on smoke_date: inclusive');

$t->get_ok('/api/searchresults?date_to=2022-07-30')
  ->status_is(200)
  ->json_is('/report_count' => 0, 'date_to before smoke_date: excluded');

# --- selected_summary filter (was missing from the API controller) ---

$t->get_ok('/api/searchresults?selected_summary=PASS')
  ->status_is(200)
  ->json_is('/report_count' => 1, 'selected_summary=PASS: matches');

$t->get_ok('/api/searchresults?selected_summary=FAIL(*)')
  ->status_is(200)
  ->json_is('/report_count' => 0, 'selected_summary=FAIL(*): no match');

# --- selected_smkv filter (was missing from the API controller) ---
# The fixture's smoke_version is 1.77.

$t->get_ok('/api/searchresults?selected_smkv=1.77')
  ->status_is(200)
  ->json_is('/report_count' => 1, 'selected_smkv=1.77: matches');

$t->get_ok('/api/searchresults?selected_smkv=9.99')
  ->status_is(200)
  ->json_is('/report_count' => 0, 'selected_smkv=9.99: no match');

# --- combined filters ---

$t->get_ok('/api/searchresults?date_from=2022-07-01&selected_summary=PASS&selected_smkv=1.77')
  ->status_is(200)
  ->json_is('/report_count' => 1, 'combined filters: all match');

$t->get_ok('/api/searchresults?date_from=2022-07-01&selected_summary=FAIL(*)')
  ->status_is(200)
  ->json_is('/report_count' => 0, 'combined filters: summary mismatch');

done_testing;
