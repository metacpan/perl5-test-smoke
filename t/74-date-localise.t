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

my $resp = $h->ingest_fixture('idefix-gff5bbe677.jsn');
my $rid  = $resp->{id};

# --- <time> elements in table rows (/latest) ---

$t->get_ok('/latest')->status_is(200);
my $dom = $t->tx->res->dom;

my $time_el = $dom->at('time.utc-date');
ok $time_el, '/latest has <time class="utc-date"> element';
like $time_el->attr('datetime'), qr/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/,
    'datetime attr is ISO 8601 UTC';
is $time_el->text, $time_el->attr('datetime'),
    'text content is the raw UTC value (JS localises client-side)';

# --- <time> element in full report page ---

$t->get_ok("/report/$rid")->status_is(200);
$dom = $t->tx->res->dom;

$time_el = $dom->at('time.utc-date');
ok $time_el, '/report has <time class="utc-date"> element';
like $time_el->attr('datetime'), qr/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/,
    'full report datetime attr is ISO 8601 UTC';

# --- Layout includes the localisation script ---

$t->get_ok('/latest')->status_is(200)
  ->content_like(qr/Intl\.DateTimeFormat/, 'layout includes Intl.DateTimeFormat script')
  ->content_like(qr/htmx:afterSettle/,    'script hooks into HTMX afterSettle');

# --- HTMX fragment also contains <time> elements ---

$t->get_ok('/latest?page=1&reports_per_page=100', { 'HX-Request' => 'true' })
  ->status_is(200);
$dom = $t->tx->res->dom;
$time_el = $dom->at('time.utc-date');
ok $time_el, 'HTMX fragment includes <time class="utc-date"> elements';

done_testing;
