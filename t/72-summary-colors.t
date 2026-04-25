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

my $db = $t->app->sqlite->db;
$db->query('UPDATE report SET summary = ? WHERE id = ?', 'FAIL(X)', $rid);

# /latest table row: class must be "summary-fail", not "summary-fail(x)"
$t->get_ok('/latest')->status_is(200)
  ->element_exists('td.summary-fail', 'td gets summary-fail class for FAIL(X)')
  ->element_exists_not('td.summary-fail\(x\)',
      'no literal summary-fail(x) class on td');

# /report/:id detail page: <dd> must also get summary-fail
$t->get_ok("/report/$rid")->status_is(200)
  ->element_exists('dd.summary-fail',
      'dd gets summary-fail class on full_report page');

# PASS reports should also work (sanity check)
$db->query('UPDATE report SET summary = ? WHERE id = ?', 'PASS', $rid);
$t->get_ok('/latest')->status_is(200)
  ->element_exists('td.summary-pass', 'td gets summary-pass class for PASS');
$t->get_ok("/report/$rid")->status_is(200)
  ->element_exists('dd.summary-pass',
      'dd gets summary-pass class on full_report page');

done_testing;
