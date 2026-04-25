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
is_deeply $matrix, { perl_versions => [], rows => [] },
    'empty DB: matrix is empty shape';

is_deeply $m->submatrix('lib/foo.t'), [],
    'empty DB: submatrix returns empty list';

is_deeply $m->submatrix('lib/foo.t', 'v5.42.0'), [],
    'empty DB: submatrix with pversion returns empty list';

done_testing;
