use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use TestApp;
use YAML::PP qw();

my $h = TestApp->new;
my $t = $h->t;

# YAML form
my $yaml_resp = $t->get_ok('/api/openapi/web.yaml')->status_is(200)->tx->res->body;
my $spec = eval { YAML::PP::Load($yaml_resp) };
ok !$@, "YAML parses without error: $@";
is $spec->{openapi}, '3.0.3', 'OpenAPI version is 3.0.3';
is $spec->{info}{title}, 'Perl 5 Core Smoke DB', 'title';

# JSON form
my $json_spec = $t->get_ok('/api/openapi/web.json')->status_is(200)->tx->res->json;
is $json_spec->{openapi}, '3.0.3', 'JSON spec parses';
is_deeply $json_spec->{info}, $spec->{info}, 'JSON and YAML match';

# Plain text form
$t->get_ok('/api/openapi/web')->status_is(200);

# Every documented path is registered (or aliased) in the actual app.
my %routes;
for my $r (@{ $h->app->routes->children }) {
    _walk_route($r, '', \%routes);
}

my %spec_paths = %{ $spec->{paths} };

for my $path (sort keys %spec_paths) {
    my $route_pattern = $path =~ s/\{(\w+)\}/:$1/gr;   # OpenAPI {x} -> Mojo :x
    ok exists $routes{$route_pattern}, "spec path $path is registered (as $route_pattern)";
}

# Reverse: every API route has a corresponding OpenAPI spec entry.
my @undocumented;
for my $route (sort keys %routes) {
    next if $route eq '/*whatever';
    next if $route eq '/';
    next if $route =~ m{^/(about|latest|search|matrix|submatrix|file|admin)\b};
    next if $route eq '/report/:rid';
    next if $route eq '/api/outfle/:rid'; # documented typo alias kept for legacy clients

    my $spec_path = $route =~ s/:(\w+)/{$1}/gr;   # Mojo :x -> OpenAPI {x}
    push @undocumented, $route unless exists $spec_paths{$spec_path};
}

ok !@undocumented, 'all API routes documented in OpenAPI spec'
    or diag "Undocumented routes: " . join(', ', @undocumented);

sub _walk_route ($node, $prefix, $store) {
    my $pattern = $node->pattern->unparsed // '';
    my $here    = $prefix . $pattern;
    $here = "/$here" if $here !~ m{^/};
    $store->{$here} = 1 if $node->is_endpoint;
    _walk_route($_, $here, $store) for @{ $node->children };
}

done_testing;
