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

# Status indication after the design-system rewrite:
#   - the row gets a `row-accent-<variant>` class (3px left border)
#   - the cell renders a status_pill -> <span class="badge badge-<variant>">
# The summary suffix `(X)` must NOT leak into a class name (the status
# variant is derived from the prefix only).

# /latest table row: row gets row-accent-danger, status cell holds a
# badge with badge-danger. No literal "row-accent-danger(x)" class.
$t->get_ok('/latest')->status_is(200)
  ->element_exists('tr.row-accent-danger',
      'row gets row-accent-danger class for FAIL(X)')
  ->element_exists('tr.row-accent-danger .badge.badge-danger',
      'status cell renders a danger badge')
  ->element_exists_not('tr.row-accent-danger\(x\)',
      'no literal row-accent-danger(x) class on tr');

# /report/:id detail page: dd holds a status_pill (badge.badge-danger)
$t->get_ok("/report/$rid")->status_is(200)
  ->element_exists('dd .badge.badge-danger',
      'dd renders a danger status badge on full_report page');

# PASS reports get success variants
$db->query('UPDATE report SET summary = ? WHERE id = ?', 'PASS', $rid);
$t->get_ok('/latest')->status_is(200)
  ->element_exists('tr.row-accent-success',
      'row gets row-accent-success class for PASS')
  ->element_exists('tr.row-accent-success .badge.badge-success',
      'status cell renders a success badge for PASS');
$t->get_ok("/report/$rid")->status_is(200)
  ->element_exists('dd .badge.badge-success',
      'dd renders a success status badge on full_report page for PASS');

done_testing;
