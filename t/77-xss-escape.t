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

# Build a fixture with a malicious user_note containing a script tag.
my $fixture = $h->fixture('idefix-gff5bbe677.jsn');
my $xss_payload = '<script>alert("xss")</script>';
$fixture->{sysinfo}{user_note} = $xss_payload;

my $resp = $t->post_ok('/api/report', json => { report_data => $fixture })
    ->status_is(200)->tx->res->json;
my $rid = $resp->{id};
ok $rid, "ingested report with malicious user_note (id=$rid)";

# The rendered report page must NOT contain the raw script tag.
$t->get_ok("/report/$rid")->status_is(200)
    ->content_unlike(qr/<script>alert\("xss"\)<\/script>/,
                     'user_note script tag is HTML-escaped, not rendered raw')
    ->content_like(qr/&lt;script&gt;/,
                   'user_note appears as escaped HTML entities');

# Second payload: event-handler attribute. Vary git_id to avoid 409.
my $fixture2 = $h->fixture('idefix-gff5bbe677.jsn');
$fixture2->{sysinfo}{user_note} = '<img src=x onerror=alert(1)>';
$fixture2->{sysinfo}{git_id}    = 'aa' . substr($fixture2->{sysinfo}{git_id}, 2);

my $resp2 = $t->post_ok('/api/report', json => { report_data => $fixture2 })
    ->status_is(200)->tx->res->json;
my $rid2 = $resp2->{id};
ok $rid2, "ingested report with event-handler payload (id=$rid2)";

$t->get_ok("/report/$rid2")->status_is(200)
    ->content_unlike(qr/<img src=x onerror/,
                     'event-handler XSS payload is escaped')
    ->content_like(qr/&lt;img src=x onerror/,
                   'img tag appears as escaped entities');

done_testing;
