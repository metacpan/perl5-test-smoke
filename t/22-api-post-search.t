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

my $resp = $h->ingest_fixture('idefix-gff5bbe677.jsn');
ok $resp->{id}, "ingested report $resp->{id}";

# POST with form parameters (mirrors the GET tests in 21-api-search-filters.t)
$t->post_ok('/api/searchresults' => form => { selected_host => 'idefix' })
  ->status_is(200)
  ->json_is('/report_count' => 1, 'POST finds the report by hostname');

$t->post_ok('/api/searchresults' => form => { selected_host => 'nope' })
  ->status_is(200)
  ->json_is('/report_count' => 0, 'POST with non-matching hostname returns 0');

done_testing;
