package CoreSmoke::Controller::Admin;
use v5.42;
use warnings;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub check_session ($c) {
    return 1 if $c->session('admin_user');
    $c->redirect_to('/admin/login');
    return undef;
}

sub login_page ($c) {
    $c->render(template => 'admin/login');
}

sub login ($c) {
    my $token = $c->csrf_token;
    my $submitted = $c->param('csrf_token') // '';
    unless ($submitted eq $token) {
        return $c->render(template => 'admin/login', error => 'Invalid form submission.');
    }

    my $username = $c->param('username') // '';
    my $password = $c->param('password') // '';

    if ($c->app->auth->verify_user($username, $password)) {
        $c->session(admin_user => $username);
        return $c->redirect_to('/admin/dashboard');
    }

    $c->render(template => 'admin/login', error => 'Invalid username or password.');
}

sub logout ($c) {
    $c->session(expires => 1);
    $c->redirect_to('/admin/login');
}

sub dashboard ($c) {
    my $db = $c->app->sqlite->db;

    my $user_count  = $db->query("SELECT COUNT(*) AS cnt FROM admin_user")->hash->{cnt};
    my $token_count = $db->query("SELECT COUNT(*) AS cnt FROM api_token WHERE cancelled_at IS NULL")->hash->{cnt};

    my $report_stats = $db->query(q{
        SELECT COUNT(*) AS total,
               SUM(CASE WHEN api_token_id IS NOT NULL THEN 1 ELSE 0 END) AS authenticated
        FROM report
    })->hash;

    $c->render(template => 'admin/dashboard',
        user_count    => $user_count,
        token_count   => $token_count,
        total_reports => $report_stats->{total} // 0,
        auth_reports  => $report_stats->{authenticated} // 0,
    );
}

1;
