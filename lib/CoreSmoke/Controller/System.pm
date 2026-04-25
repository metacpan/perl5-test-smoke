package CoreSmoke::Controller::System;
use v5.42;
use warnings;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;

use CoreSmoke::JsonRpc::Methods;

sub healthz ($c) {
    return $c->render(text => "ok\n");
}

sub readyz ($c) {
    my $ok = eval { $c->app->sqlite->db->query('SELECT 1')->hash; 1 };
    return $c->render(status => $ok ? 200 : 503,
                      text   => $ok ? "ready\n" : "db unavailable\n");
}

sub ping ($c) {
    my $entry = CoreSmoke::JsonRpc::Methods::method('ping');
    return $c->render(text => $entry->{call}->($c, {}));
}

sub version ($c) {
    my $entry = CoreSmoke::JsonRpc::Methods::method('version');
    return $c->render(json => $entry->{call}->($c, {}));
}

sub status ($c) {
    my $entry = CoreSmoke::JsonRpc::Methods::method('status');
    return $c->render(json => $entry->{call}->($c, {}));
}

sub list_methods ($c) {
    my $plugin = $c->stash('plugin');
    my $names  = CoreSmoke::JsonRpc::Methods::method('list_methods')->{call}
        ->($c, { plugin => $plugin });
    return $c->render(json => { methods => $names, ($plugin ? (plugin => $plugin) : ()) });
}

1;
