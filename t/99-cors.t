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

for my $path (qw(
    /api/version
    /api/latest
    /api/searchparameters
    /api/matrix
    /system/ping
    /healthz
)) {
    $t->get_ok($path)->status_is(200)
      ->header_is('Access-Control-Allow-Origin' => '*', "$path has CORS *");
}

done_testing;
