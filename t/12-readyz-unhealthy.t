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

# Override the sqlite helper to simulate a DB failure.
$t->app->helper(sqlite => sub { die "db gone" });

$t->get_ok('/readyz')
  ->status_is(503)
  ->content_like(qr/unavailable/);

done_testing;
