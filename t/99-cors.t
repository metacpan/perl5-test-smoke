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

# GET endpoints receive CORS wildcard
for my $path (qw(
    /api/version
    /api/latest
    /api/searchparameters
    /api/matrix
    /system/ping
    /healthz
)) {
    $t->get_ok($path)->status_is(200)
      ->header_is('Access-Control-Allow-Origin' => '*', "GET $path has CORS *")
      ->header_like('Access-Control-Allow-Methods' => qr/GET/, "GET $path allows GET");
}

# POST endpoints must NOT have CORS headers (prevents cross-origin abuse)
for my $path (qw(
    /api/report
    /api
    /system
)) {
    $t->post_ok($path)->header_is('Access-Control-Allow-Origin' => undef,
        "POST $path has no CORS origin header");
}

done_testing;
