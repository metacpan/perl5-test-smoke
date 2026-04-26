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

# Ingest with a non-ISO smoke_date that exercises Date::Parse text parsing.
my $body = $h->fixture('idefix-gff5bbe677.jsn');
$body->{sysinfo}{smoke_date} = 'Jul 31 2022 01:05:08';

$t->post_ok('/api/report', json => { report_data => $body })
  ->status_is(200);

my $rid = $t->tx->res->json->{id};
ok $rid, "ingested report $rid";

my $row = $h->app->sqlite->db->query(
    "SELECT smoke_date FROM report WHERE id = ?", $rid
)->hash;

like $row->{smoke_date}, qr/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/,
     'non-ISO smoke_date normalised to ISO 8601 UTC';

done_testing;
