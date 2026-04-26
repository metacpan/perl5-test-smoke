use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use TestApp;
use Mojo::JSON qw(decode_json);
use Mojo::File qw();

my $h = TestApp->new;
my $t = $h->t;

my $fixture = $h->fixture('idefix-gff5bbe677.jsn');

# Inject XSS payload into a failure test name and status
my $xss_test   = '<img src=x onerror=alert(document.domain)>';
my $xss_status = '<script>alert(1)</script>';
$fixture->{configs}[0]{results}[0]{failures} = [
    { test => $xss_test, status => $xss_status, extra => 'details' },
];
$fixture->{summary} = 'FAIL';

my $resp = $t->post_ok('/api/report', json => { report_data => $fixture })
    ->status_is(200)
    ->tx->res->json;
my $rid = $resp->{id};
ok $rid, "report with XSS payload ingested ($rid)";

# Fetch the full report page and check the raw XSS payload does NOT appear
$t->get_ok("/report/$rid")->status_is(200)
    ->content_unlike(qr/<img src=x onerror/,
        'XSS img tag in failure test name is escaped')
    ->content_unlike(qr/<script>alert/,
        'XSS script tag in failure status is escaped');

# The escaped form should be present instead
$t->content_like(qr/&lt;img src=x onerror/,
    'failure test name is HTML-escaped in output');
$t->content_like(qr/&lt;script&gt;alert/,
    'failure status is HTML-escaped in output');

done_testing;
