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

my $XSS = '<img src=x onerror=alert(1)>';
my $XSS_ESC = '&lt;img src=x onerror=alert(1)&gt;';

# --- Reflected XSS via /submatrix?test= ---
# The page_header title uses <%== (raw output) to allow <code> tags.
# The test and pversion params must be escaped before interpolation.
subtest 'reflected XSS in /submatrix title' => sub {
    $t->get_ok("/submatrix?test=$XSS")
        ->status_is(200)
        ->content_unlike(qr/onerror=alert/,
            'script payload must not appear unescaped in page body')
        ->content_like(qr/\Q$XSS_ESC\E/,
            'test param appears as escaped entities');
};

# --- Stored XSS via perl_id in /matrix column headers ---
# data_table headers use <%== to allow inline <code> markup.
# perl_id values from the DB must be escaped before wrapping in HTML.
subtest 'stored XSS via perl_id in matrix headers' => sub {
    my $fixture = $h->fixture('idefix-gff5bbe677.jsn');
    $fixture->{sysinfo}{perl_id} = $XSS;
    $fixture->{sysinfo}{git_id} = 'bb' . substr($fixture->{sysinfo}{git_id}, 2);

    # Need at least one failure for the test to show in the matrix
    $fixture->{configs}[0]{results}[0]{summary} = 'F';
    $fixture->{configs}[0]{results}[0]{failures} = [
        { test => 'op/xss-test.t', status => 'FAILED', extra => '' },
    ];

    my $resp = $t->post_ok('/api/report', json => { report_data => $fixture })
        ->status_is(200)->tx->res->json;
    ok $resp->{id}, "ingested report with XSS perl_id (id=$resp->{id})";

    $t->get_ok('/matrix')
        ->status_is(200)
        ->content_unlike(qr/onerror=alert/,
            'XSS perl_id must not appear raw in matrix column headers')
        ->content_like(qr/\Q$XSS_ESC\E/,
            'perl_id appears as escaped entities in matrix headers');
};

# --- Stored XSS via io_env in /report/:id config table headers ---
# The full_report view passes io_labels (from DB io_env values) as
# data_table headers, which renders them with <%==.
subtest 'stored XSS via io_env in report config headers' => sub {
    my $fixture = $h->fixture('idefix-gff5bbe677.jsn');
    $fixture->{sysinfo}{git_id} = 'cc' . substr($fixture->{sysinfo}{git_id}, 2);

    # Replace the io_env in one result with an XSS payload
    $fixture->{configs}[0]{results}[0]{io_env} = $XSS;

    my $resp = $t->post_ok('/api/report', json => { report_data => $fixture })
        ->status_is(200)->tx->res->json;
    my $rid = $resp->{id};
    ok $rid, "ingested report with XSS io_env (id=$rid)";

    $t->get_ok("/report/$rid")
        ->status_is(200)
        ->content_unlike(qr/onerror=alert/,
            'XSS io_env must not appear raw in config table headers')
        ->content_like(qr/\Q$XSS_ESC\E/,
            'io_env appears as escaped entities in config headers');
};

done_testing;
