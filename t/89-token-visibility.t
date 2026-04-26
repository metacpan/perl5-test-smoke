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

# Create a token and ingest a report with it
my $tok   = $h->app->auth->create_token(note => 'visibility-test', email => 'viz@example.com');
my $token = $tok->{token};

# Ingest with token
my $fixture = $h->fixture('idefix-gff5bbe677.jsn');
$t->post_ok('/api/report',
    { Authorization => "Bearer $token" },
    json => { report_data => $fixture },
)->status_is(200);
my $rid = $t->tx->res->json->{id};

subtest 'full_report_data includes trust indicator' => sub {
    $t->get_ok("/api/full_report_data/$rid")
      ->status_is(200)
      ->json_is('/authenticated' => \1)
      ->json_is('/token_note' => 'visibility-test')
      ->json_is('/token_email' => 'viz@example.com');
};

subtest 'report detail page shows Authenticated badge' => sub {
    $t->get_ok("/report/$rid")
      ->status_is(200)
      ->content_like(qr/Authenticated/);
};

subtest 'latest page renders with Trust column' => sub {
    $t->get_ok('/latest')
      ->status_is(200)
      ->content_like(qr/Trust/);
};

# Ingest without token and verify unauthenticated in API
my %copy = %$fixture;
my %sys = %{ $copy{sysinfo} // {} };
$sys{hostname} = 'unauthed-host';
$copy{sysinfo} = \%sys;

$t->post_ok('/api/report', json => { report_data => \%copy })
    ->status_is(200);
my $rid2 = $t->tx->res->json->{id};

subtest 'unauthenticated report in API' => sub {
    $t->get_ok("/api/full_report_data/$rid2")
      ->status_is(200)
      ->json_is('/authenticated' => \0);
};

subtest 'report detail page shows Unauthenticated' => sub {
    $t->get_ok("/report/$rid2")
      ->status_is(200)
      ->content_like(qr/Unauthenticated/);
};

done_testing;
