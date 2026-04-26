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

# --- commify ---

is $c->commify(1234567),  '1,234,567', 'millions';
is $c->commify(42),       '42',        'no separator needed';
is $c->commify(undef),    '0',         'undef returns 0';
is $c->commify(''),       '0',         'empty string returns 0';
is $c->commify(0),        '0',         'zero';
is $c->commify(1000),     '1,000',     'thousands boundary';
is $c->commify(-1234567), '-1,234,567','negative number';

# --- summary_desc ---

is $c->summary_desc('O'), 'OK',              'O maps to OK';
is $c->summary_desc('F'), 'harness failure',  'F maps to harness failure';
is $c->summary_desc('c'), 'Configure failure','c maps to Configure failure';
is $c->summary_desc('Z'), 'Z',               'unknown code passes through';
is $c->summary_desc(undef), 'N/A',           'undef returns N/A';
is $c->summary_desc(''),    'N/A',           'empty returns N/A';

done_testing;
