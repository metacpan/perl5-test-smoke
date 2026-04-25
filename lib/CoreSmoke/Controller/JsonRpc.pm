package CoreSmoke::Controller::JsonRpc;
use v5.42;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;

# Stub. Plan 04 fills this in.

sub dispatch ($c) {
    return $c->render(status => 501, json => {
        jsonrpc => '2.0',
        id      => undef,
        error   => { code => -32603, message => 'Not implemented yet' },
    });
}

1;
