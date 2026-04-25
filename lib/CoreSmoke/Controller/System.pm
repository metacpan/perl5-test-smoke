package CoreSmoke::Controller::System;
use v5.42;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Sys::Hostname qw(hostname);

my $STARTED = time;

sub healthz ($c) {
    return $c->render(text => "ok\n");
}

sub readyz ($c) {
    my $ok = eval { $c->app->sqlite->db->query('SELECT 1')->hash; 1 };
    return $c->render(status => $ok ? 200 : 503,
                      text   => $ok ? "ready\n" : "db unavailable\n");
}

sub ping ($c) {
    return $c->render(text => 'pong');
}

sub version ($c) {
    return $c->render(json => { software_version => $c->app->config->{app_version} // '2.0' });
}

sub status ($c) {
    return $c->render(json => {
        app_version  => $c->app->config->{app_version} // '2.0',
        app_name     => $c->app->config->{app_name}    // 'Perl 5 Core Smoke DB',
        active_since => $STARTED,
        hostname     => hostname,
        running_pid  => $$,
        dancer2      => Mojolicious->VERSION,   # legacy key carried; value is Mojo's
        rpc_plugin   => 'CoreSmoke::Controller::JsonRpc',
    });
}

sub list_methods ($c) {
    # Stub. Plan 04 fills this in via JsonRpc/Methods registry.
    my $plugin = $c->stash('plugin');
    return $c->render(json => { methods => [], plugin => $plugin });
}

1;
