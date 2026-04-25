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

# Empty DB
$t->get_ok('/')      ->status_is(200)->text_like('h1' => qr/Latest smoke results/);
$t->get_ok('/latest')->status_is(200);
$t->get_ok('/search')->status_is(200);
$t->get_ok('/matrix')->status_is(200);
$t->get_ok('/about') ->status_is(200);
$t->get_ok('/report/9999')        ->status_is(404);
$t->get_ok('/file/log_file/9999') ->status_is(404);
$t->get_ok('/file/out_file/9999') ->status_is(404);

# Layout includes the nav
$t->get_ok('/latest')->status_is(200)
  ->text_like('nav a' => qr/Latest|Search|Matrix|About/);

# Ingest a fixture and check the populated pages render
my $resp = $h->ingest_fixture('idefix-gff5bbe677.jsn');
my $rid  = $resp->{id};

$t->get_ok('/latest')->status_is(200)
  ->content_like(qr/idefix/);                 # hostname appears in row

$t->get_ok("/report/$rid")->status_is(200)
  ->text_like('h1' => qr/Smoke report #\Q$rid\E/)
  ->content_like(qr/v5\.37/, 'full_report shows git_describe value');

# manifest_msgs is on disk; the file route reads it back through xz
# (we ingested an empty log_file so log_file path stays 404)
$t->get_ok("/file/log_file/$rid")->status_is(404);

# About page shows Perl + Mojo + DB versions
$t->get_ok('/about')->status_is(200)
  ->content_like(qr/Mojolicious/)
  ->content_like(qr/SQLite/)
  ->content_like(qr/DB version/);

done_testing;
