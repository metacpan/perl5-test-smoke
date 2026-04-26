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

# --- X-Content-Type-Options and X-Frame-Options on all methods ---

for my $path (qw( /api/version /api/latest /healthz )) {
    $t->get_ok($path)->status_is(200)
      ->header_is('X-Content-Type-Options' => 'nosniff', "GET $path has nosniff")
      ->header_is('X-Frame-Options'        => 'DENY',    "GET $path has DENY framing");
}

for my $path (qw( /api/report /api /system )) {
    $t->post_ok($path)
      ->header_is('X-Content-Type-Options' => 'nosniff', "POST $path has nosniff")
      ->header_is('X-Frame-Options'        => 'DENY',    "POST $path has DENY framing");
}

# --- Content-Security-Policy on GET responses ---

$t->get_ok('/latest')->status_is(200);
my $csp = $t->tx->res->headers->header('Content-Security-Policy');
ok $csp, 'CSP header present on GET /latest';

like $csp, qr/default-src 'self'/,      'CSP: default-src self';
like $csp, qr/script-src 'self' 'nonce-/, 'CSP: script-src includes nonce';
like $csp, qr/style-src/,               'CSP: style-src present';
like $csp, qr/font-src/,                'CSP: font-src present';
like $csp, qr/frame-ancestors 'none'/,  'CSP: frame-ancestors none';

# --- Nonce in CSP matches nonce in rendered HTML ---

my $body = $t->tx->res->body;
my ($html_nonce) = $body =~ /nonce="([^"]+)"/;
ok $html_nonce, 'inline script has a nonce attribute';

my ($csp_nonce) = $csp =~ /'nonce-([^']+)'/;
ok $csp_nonce, 'CSP header contains a nonce value';
is $csp_nonce, $html_nonce, 'CSP nonce matches HTML script nonce';

# --- Nonce changes between requests ---

$t->get_ok('/latest')->status_is(200);
my $csp2 = $t->tx->res->headers->header('Content-Security-Policy');
my ($csp_nonce2) = $csp2 =~ /'nonce-([^']+)'/;
ok $csp_nonce2, 'second request has a nonce';
isnt $csp_nonce2, $csp_nonce, 'nonce differs between requests';

done_testing;
