package CoreSmoke::Controller::Ingest;
use v5.42;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;

# Stubs. Plan 05 fills these in.

sub post_report ($c) {
    return $c->render(status => 501, json => { error => 'Not implemented yet: Ingest#post_report' });
}

sub post_old_format_report ($c) {
    return $c->render(status => 501, json => { error => 'Not implemented yet: Ingest#post_old_format_report' });
}

1;
