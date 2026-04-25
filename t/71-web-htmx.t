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

# HX-Request flips /latest into a fragment template (no <html>, no <body>)
$t->get_ok('/latest', { 'HX-Request' => 'true' })
  ->status_is(200)
  ->content_unlike(qr{<html|<body}, '/latest with HX-Request returns fragment');

$t->get_ok('/search?selected_perl=all', { 'HX-Request' => 'true' })
  ->status_is(200)
  ->content_unlike(qr{<html|<body}, '/search with HX-Request returns fragment');

# Without HX-Request, full page including layout
$t->get_ok('/latest')->status_is(200)
  ->content_like(qr{<html}, '/latest without HX-Request returns full page');

done_testing;
