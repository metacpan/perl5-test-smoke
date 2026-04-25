use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use TestApp;
use Mojo::JSON qw(encode_json);
use Mojo::URL  qw();
use Mojo::Util qw(url_escape);

my $h = TestApp->new;
my $t = $h->t;

my $body = encode_json($h->fixture('idefix-gff5bbe677.jsn'));

# /api/old_format_reports accepts form-urlencoded `json=...`
$t->post_ok('/api/old_format_reports' =>
    { 'Content-Type' => 'application/x-www-form-urlencoded' } =>
    form => { json => $body }
)->status_is(200)->json_has('/id');

my $id = $t->tx->res->json('/id');
ok $id, "old-format ingest returned id ($id)";

# Built-in /report alias (decision #10)
TestApp::reset_db();
$h = TestApp->new;
$t = $h->t;

$t->post_ok('/report' =>
    { 'Content-Type' => 'application/x-www-form-urlencoded' } =>
    form => { json => $body }
)->status_is(200)->json_has('/id');

# Missing json param
$t->post_ok('/api/old_format_reports' =>
    { 'Content-Type' => 'application/x-www-form-urlencoded' } =>
    form => { }
)->status_is(422);

# Bad JSON
$t->post_ok('/api/old_format_reports' =>
    { 'Content-Type' => 'application/x-www-form-urlencoded' } =>
    form => { json => 'not-json{' }
)->status_is(400);

done_testing;
