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

# Ingest a fixture with non-empty log_file and out_file content
my $fixture = $h->fixture('idefix-gff5bbe677.jsn');
$fixture->{log_file} = "Started smoke at 2022-07-31 03:05:08\nBuilding perl\nAll tests successful.\n";
$fixture->{out_file} = "   cc -o miniperl ...\n   Running make test\n   All tests successful.\n";

$t->post_ok('/api/report', json => { report_data => $fixture })
  ->status_is(200);
my $rid = $t->tx->res->json->{id};

# GET /file/log_file/:rid returns 200 with decompressed content
$t->get_ok("/file/log_file/$rid")
  ->status_is(200)
  ->content_like(qr/Started smoke at 2022-07-31/)
  ->content_like(qr/All tests successful/);

# GET /file/out_file/:rid returns 200 with decompressed content
$t->get_ok("/file/out_file/$rid")
  ->status_is(200)
  ->content_like(qr/cc -o miniperl/)
  ->content_like(qr/Running make test/);

# Content is rendered inside the plain_text template (code_block component)
$t->get_ok("/file/log_file/$rid")
  ->status_is(200)
  ->element_exists('pre', 'content rendered in a <pre> block')
  ->content_like(qr/log_file/, 'page title shows field name');

# Breadcrumbs link back to the report
$t->get_ok("/file/out_file/$rid")
  ->status_is(200)
  ->element_exists(qq{a[href="/report/$rid"]}, 'breadcrumb links back to report');

# Nonexistent report returns 404
$t->get_ok('/file/log_file/99999')->status_is(404);
$t->get_ok('/file/out_file/99999')->status_is(404);

done_testing;
