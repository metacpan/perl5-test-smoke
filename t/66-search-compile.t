use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use TestApp;
use CoreSmoke::Model::Search;

my $h     = TestApp->new;
my $sqlite = $h->app->sqlite;
my $s     = CoreSmoke::Model::Search->new(sqlite => $sqlite);

# Empty params -> no filter
{
    my ($from, $where, $bind) = $s->compile({});
    is $from, "FROM report r", 'empty params: no config join';
    is $where, '', 'empty params: no where clause';
    is_deeply $bind, [], 'empty params: no bind values';
}

# Single equality on architecture
{
    my ($from, $where, $bind) = $s->compile({ selected_arch => 'x86_64' });
    is $from, "FROM report r", 'arch only: no config join';
    like $where, qr/r\.architecture = \?/, 'arch =';
    is_deeply $bind, ['x86_64'], 'bind value';
}

# AND/NOT inversion flips equality to inequality
{
    my ($from, $where, $bind) = $s->compile({
        selected_arch  => 'x86_64',
        andnotsel_arch => 1,
    });
    like $where, qr/r\.architecture <> \?/, 'and-not flips to <>';
    is_deeply $bind, ['x86_64'], 'bind value';
}

# `latest` is resolved by Reports::searchresults / available_filter_values
# into a concrete perl_id (via RPM-style sort) before Search::compile is
# called, so the compiler treats `latest` as a no-op and emits no clause.
{
    my ($from, $where, $bind) = $s->compile({ selected_perl => 'latest' });
    is $where, '', 'compile leaves bare `latest` untouched';
    is_deeply $bind, [], 'no bind for latest';
}

# Compiler filters force the config join
{
    my ($from, $where, $bind) = $s->compile({ selected_comp => 'gcc' });
    like $from, qr/JOIN config c/, 'comp triggers config join';
    like $where, qr/c\.cc = \?/, 'cc = ?';
    is_deeply $bind, ['gcc'], 'bind value';
}

# Smoker version filter uses report table
{
    my ($from, $where, $bind) = $s->compile({ selected_smkv => '1.86' });
    is $from, "FROM report r", 'smkv only: no config join';
    like $where, qr/r\.smoke_version = \?/, 'smoke_version =';
    is_deeply $bind, ['1.86'], 'bind value';
}

# `all` is treated as no filter
{
    my (undef, $where, $bind) = $s->compile({
        selected_arch => 'all',
        selected_perl => 'all',
    });
    is $where, '', 'all -> no where';
    is_deeply $bind, [], 'all -> no bind';
}

# run() against an empty DB returns the empty shape
{
    my $out = $s->run({});
    is $out->{report_count},     0,  'empty DB: 0 reports';
    is_deeply $out->{reports},   [], 'empty DB: empty list';
    is $out->{page},             1,  'default page';
    is $out->{reports_per_page}, 25, 'default rpp';
}

done_testing;
