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

# Ingest a fixture so dropdowns have data to return.
my $resp = $h->ingest_fixture('idefix-gff5bbe677.jsn');
ok $resp->{id}, 'fixture ingested';

my $reports = $h->app->reports;

# --- No filters: all 10 dimensions populated ---------------------------------

{
    my $av = $reports->available_filter_values({});
    my @expected_dims = sort qw(
        architectures osnames osversions perl_versions branches
        hostnames compilers compiler_versions smoker_versions summaries
    );
    is_deeply [sort keys %$av], \@expected_dims,
        'all 10 dimension keys present';

    for my $dim (@expected_dims) {
        ok ref $av->{$dim} eq 'ARRAY', "$dim is an arrayref";
        ok scalar @{ $av->{$dim} } >= 1, "$dim has at least one value"
            or diag "$dim values: @{ $av->{$dim} }";
    }

    # The fixture's hostname is "idefix"
    ok( (grep { $_ eq 'idefix' } @{ $av->{hostnames} }),
        'hostnames includes idefix' );

    # Smoker version from fixture (1.77)
    ok( (grep { $_ eq '1.77' } @{ $av->{smoker_versions} }),
        'smoker_versions includes 1.77' );

    # Summary should be bucketed (PASS, not raw PASS value)
    ok( (grep { $_ eq 'PASS' } @{ $av->{summaries} }),
        'summaries includes PASS bucket' );
}

# --- Filter on architecture: hostname dropdown still shows idefix -------------

{
    my $av = $reports->available_filter_values({
        selected_arch => $reports->available_filter_values({})->{architectures}[0],
    });
    ok( (grep { $_ eq 'idefix' } @{ $av->{hostnames} }),
        'hostname survives when filtering by matching architecture' );
}

# --- Filter on a non-existent value: other dims may be empty ------------------

{
    my $av = $reports->available_filter_values({
        selected_arch => 'NONEXISTENT_ARCH_42',
    });
    is_deeply $av->{hostnames}, [],
        'impossible filter yields empty hostnames';
    is_deeply $av->{perl_versions}, [],
        'impossible filter yields empty perl_versions';
    # Architecture dropdown itself should still show all values (its own
    # filter is excluded), so architectures should NOT be empty.
    ok scalar @{ $av->{architectures} } >= 1,
        'architecture dropdown still populated (own filter excluded)';
}

# --- 'latest' perl filter resolves correctly ----------------------------------

{
    my $av = $reports->available_filter_values({ selected_perl => 'latest' });
    ok ref $av->{architectures} eq 'ARRAY',
        'latest perl filter does not crash';
}

done_testing;
