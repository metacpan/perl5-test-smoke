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

# Bootstrap an admin user
$h->app->auth->create_user('admin', 'testpass');

subtest 'unauthenticated access redirects to login' => sub {
    $t->get_ok('/admin/dashboard')
      ->status_is(302)
      ->header_like('Location' => qr{/admin/login});
};

subtest 'login page renders' => sub {
    $t->get_ok('/admin/login')
      ->status_is(200)
      ->content_like(qr/Admin Login/);
};

subtest 'login with wrong credentials' => sub {
    # First get the login page to obtain a CSRF token via the session
    $t->get_ok('/admin/login')->status_is(200);
    my $csrf = $t->tx->res->dom->at('input[name=csrf_token]')->attr('value');
    ok $csrf, 'got CSRF token';

    $t->post_ok('/admin/login', form => {
        csrf_token => $csrf,
        username   => 'admin',
        password   => 'wrongpass',
    })->status_is(200)
      ->content_like(qr/Invalid username or password/);
};

subtest 'login with correct credentials' => sub {
    $t->get_ok('/admin/login')->status_is(200);
    my $csrf = $t->tx->res->dom->at('input[name=csrf_token]')->attr('value');

    $t->post_ok('/admin/login', form => {
        csrf_token => $csrf,
        username   => 'admin',
        password   => 'testpass',
    })->status_is(302)
      ->header_like('Location' => qr{/admin/dashboard});
};

subtest 'authenticated access to dashboard' => sub {
    $t->get_ok('/admin/dashboard')
      ->status_is(200)
      ->content_like(qr/Admin Dashboard/);
};

subtest 'logout clears session' => sub {
    $t->post_ok('/admin/logout')
      ->status_is(302)
      ->header_like('Location' => qr{/admin/login});

    $t->get_ok('/admin/dashboard')
      ->status_is(302)
      ->header_like('Location' => qr{/admin/login});
};

done_testing;
