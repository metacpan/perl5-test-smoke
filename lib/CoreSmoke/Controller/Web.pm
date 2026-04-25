package CoreSmoke::Controller::Web;
use v5.42;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;

# Stubs. Plan 07 fills these in.

sub _stub ($c, $name) {
    return $c->render(status => 501, text => "Not implemented yet: Web#$name");
}

sub latest      ($c) { _stub($c, 'latest') }
sub search      ($c) { _stub($c, 'search') }
sub matrix      ($c) { _stub($c, 'matrix') }
sub submatrix   ($c) { _stub($c, 'submatrix') }
sub about       ($c) { _stub($c, 'about') }
sub full_report ($c) { _stub($c, 'full_report') }
sub log_file    ($c) { _stub($c, 'log_file') }
sub out_file    ($c) { _stub($c, 'out_file') }
sub not_found   ($c) { $c->render(status => 404, text => 'Not Found') }

1;
