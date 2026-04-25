use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use TestApp;
use CoreSmoke::Model::Matrix;

my $h = TestApp->new;
my $m = CoreSmoke::Model::Matrix->new(sqlite => $h->app->sqlite);

my $matrix = $m->matrix;
is_deeply $matrix, { perl_versions => [], rows => [],
                     test_count => 0, hot_failures => 0 },
    'empty DB: matrix is empty shape';

my $paginated = $m->matrix(page => 1, rows_per_page => 25);
is_deeply $paginated, { perl_versions => [], rows => [],
                        test_count => 0, hot_failures => 0 },
    'empty DB: paginated matrix is empty shape';

is_deeply $m->submatrix('lib/foo.t'), [],
    'empty DB: submatrix returns empty list';

is_deeply $m->submatrix('lib/foo.t', 'v5.42.0'), [],
    'empty DB: submatrix with pversion returns empty list';

# Web endpoint renders without errors
my $t = $h->t;
$t->get_ok('/matrix')->status_is(200)
  ->content_like(qr/No reports yet/, 'empty matrix shows empty state');

$t->get_ok('/matrix?page=1&rows_per_page=25')->status_is(200)
  ->content_like(qr/No reports yet/, 'paginated empty matrix shows empty state');

# HTMX request on empty matrix returns empty fragment
$t->get_ok('/matrix?page=1&rows_per_page=25',
    { 'HX-Request' => 'true' }
)->status_is(200);

done_testing;
