package CoreSmoke::Controller::Api;
use v5.42;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;

# Stubs. Plan 03 fills these in.

sub _stub ($c, $name) {
    return $c->render(status => 501, json => { error => "Not implemented yet: Api#$name" });
}

sub version          ($c) { return $c->render(json => $c->app->reports->version) }
sub latest           ($c) { _stub($c, 'latest') }
sub full_report_data ($c) { _stub($c, 'full_report_data') }
sub report_data      ($c) { _stub($c, 'report_data') }
sub logfile          ($c) { _stub($c, 'logfile') }
sub outfile          ($c) { _stub($c, 'outfile') }
sub matrix           ($c) { _stub($c, 'matrix') }
sub submatrix        ($c) { _stub($c, 'submatrix') }
sub searchparameters ($c) { _stub($c, 'searchparameters') }
sub searchresults    ($c) { _stub($c, 'searchresults') }
sub reports_from_id  ($c) { _stub($c, 'reports_from_id') }
sub reports_from_epoch ($c) { _stub($c, 'reports_from_epoch') }
sub openapi_json     ($c) { _stub($c, 'openapi_json') }
sub openapi_yaml     ($c) { _stub($c, 'openapi_yaml') }
sub openapi_text     ($c) { _stub($c, 'openapi_text') }

1;
