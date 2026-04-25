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
my $c = $t->app->build_controller;

# --- Helper unit tests ---

is($c->duration_hms(0),     '0s',           '0 seconds');
is($c->duration_hms(undef), '0s',           'undef');
is($c->duration_hms(''),    '0s',           'empty string');
is($c->duration_hms(42),    '42s',          'seconds only');
is($c->duration_hms(60),    '1m 0s',        'exactly one minute');
is($c->duration_hms(125),   '2m 5s',        'minutes and seconds');
is($c->duration_hms(3600),  '1h 0m 0s',     'exactly one hour');
is($c->duration_hms(3800),  '1h 3m 20s',    'hours, minutes, seconds');
is($c->duration_hms(7261),  '2h 1m 1s',     'multi-hour');

# --- Template integration ---

my $resp = $h->ingest_fixture('idefix-gff5bbe677.jsn');
my $rid  = $resp->{id};

$t->get_ok("/report/$rid")->status_is(200)
  ->content_like(qr/1h 3m 20s/,  'config duration 3800 rendered as 1h 3m 20s')
  ->content_like(qr/1h 8m 20s/,  'config duration 4100 rendered as 1h 8m 20s')
  ->content_unlike(qr/3800\s*s/, 'raw 3800 s no longer appears')
  ->content_unlike(qr/4100\s*s/, 'raw 4100 s no longer appears');

done_testing;
