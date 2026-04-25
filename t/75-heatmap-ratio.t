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
my $c = $t->app->build_controller;

# --- Edge cases ---

is($c->heatmap_ratio(0),     0,  'zero count => 0');
is($c->heatmap_ratio(undef), 0,  'undef => 0');
is($c->heatmap_ratio(''),    0,  'empty string => 0');
is($c->heatmap_ratio(-1),    0,  'negative => 0');

# --- Log-scale curve ---
# Formula: floor(10 + 20 * log10(n)), clamped to [10, 80]

is($c->heatmap_ratio(1),    10, 'cnt=1 => 10 (log10(1)=0, 10+0=10)');
is($c->heatmap_ratio(2),    16, 'cnt=2 => 16 (floor(10 + 20*0.301))');
is($c->heatmap_ratio(10),   30, 'cnt=10 => 30 (10 + 20*1)');
is($c->heatmap_ratio(100),  50, 'cnt=100 => 50 (10 + 20*2)');
is($c->heatmap_ratio(1000), 70, 'cnt=1000 => 70 (10 + 20*3)');

# --- Clamp at 80 ---

is($c->heatmap_ratio(10000),  80, 'cnt=10000 => clamped to 80');
is($c->heatmap_ratio(100000), 80, 'cnt=100000 => clamped to 80');

# --- Floor minimum at 10 for positive counts ---
# log10(1) = 0, so floor(10+0) = 10; values below 1 aren't realistic
# but the clamp protects against fractional inputs.

done_testing;
