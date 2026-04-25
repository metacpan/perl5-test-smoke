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

$t->get_ok('/system/ping')->status_is(200)->content_is('pong');

$t->get_ok('/system/version')->status_is(200)
  ->json_is('/software_version' => '2.0');

$t->get_ok('/system/status')->status_is(200)
  ->json_has('/active_since')
  ->json_has('/hostname')
  ->json_has('/running_pid')
  ->json_is('/app_name' => 'Perl 5 Core Smoke DB (test)');

$t->get_ok('/system/methods')->status_is(200)
  ->json_has('/methods');

my $all = $t->tx->res->json('/methods');
ok scalar(@$all) >= 10, "at least 10 methods registered (got " . scalar(@$all) . ")";
ok( (grep { $_ eq 'ping' }   @$all), 'ping is in the registry');
ok( (grep { $_ eq 'latest' } @$all), 'latest is in the registry');

$t->get_ok('/system/methods/api')->status_is(200)
  ->json_is('/plugin' => 'api');

my $api = $t->tx->res->json('/methods');
ok scalar(@$api) > 0, 'api plugin has methods';
ok !( grep { $_ eq 'ping' } @$api ), 'ping (system) is NOT in api filter';
ok( ( grep { $_ eq 'latest' } @$api ), 'latest IS in api filter');

# Health
$t->get_ok('/healthz')->status_is(200)->content_like(qr/^ok/);
$t->get_ok('/readyz') ->status_is(200)->content_like(qr/^ready/);

done_testing;
