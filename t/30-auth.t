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
my $auth = $h->app->auth;

# --- Admin users ---

subtest 'create and verify admin user' => sub {
    my $res = $auth->create_user('admin', 'secret123');
    ok $res->{ok}, 'create_user succeeds';

    ok $auth->verify_user('admin', 'secret123'), 'verify with correct password';
    ok !$auth->verify_user('admin', 'wrongpass'), 'reject wrong password';
    ok !$auth->verify_user('nonexistent', 'secret123'), 'reject unknown user';
};

subtest 'duplicate username rejected' => sub {
    my $res = $auth->create_user('admin', 'other');
    is $res->{error}, 'User already exists.', 'UNIQUE constraint fires';
};

subtest 'list users' => sub {
    my $users = $auth->list_users;
    is scalar(@$users), 1, 'one user in list';
    is $users->[0]{username}, 'admin', 'username matches';
    ok $users->[0]{created_at}, 'created_at populated';
};

subtest 'update password' => sub {
    my $res = $auth->update_password('admin', 'newpass');
    ok $res->{ok}, 'update_password succeeds';
    ok $auth->verify_user('admin', 'newpass'), 'new password works';
    ok !$auth->verify_user('admin', 'secret123'), 'old password rejected';
};

subtest 'update password for nonexistent user' => sub {
    my $res = $auth->update_password('ghost', 'pw');
    is $res->{error}, 'User not found.', 'returns error';
};

subtest 'delete user (blocked when last)' => sub {
    my $res = $auth->delete_user('admin');
    is $res->{error}, 'Cannot delete the last admin user.', 'cannot delete last admin';
};

subtest 'delete user (allowed when not last)' => sub {
    $auth->create_user('admin2', 'pw2');
    my $res = $auth->delete_user('admin2');
    ok $res->{ok}, 'second user deleted';

    my $users = $auth->list_users;
    is scalar(@$users), 1, 'back to one user';
};

# --- API tokens ---

subtest 'create and validate token' => sub {
    my $tok = $auth->create_token(note => 'CI bot', email => 'ci@example.com');
    ok $tok, 'token created';
    like $tok->{token}, qr/^[a-f0-9]{64}$/, 'token is 64 hex chars';
    is $tok->{note}, 'CI bot', 'note stored';
    is $tok->{email}, 'ci@example.com', 'email stored';
    is $tok->{use_count}, 0, 'use_count starts at 0';

    my $valid = $auth->validate_token($tok->{token});
    ok $valid, 'validate_token returns row for active token';
    is $valid->{id}, $tok->{id}, 'same token id';
};

subtest 'list tokens' => sub {
    my $tokens = $auth->list_tokens;
    ok scalar(@$tokens) >= 1, 'at least one token in list';
};

subtest 'cancel token' => sub {
    my $tok = $auth->create_token(note => 'temp');
    ok $auth->validate_token($tok->{token}), 'active before cancel';

    my $res = $auth->cancel_token($tok->{id});
    ok $res->{ok}, 'cancel succeeds';

    ok !$auth->validate_token($tok->{token}), 'cancelled token rejected by validate';

    my $row = $auth->get_token($tok->{id});
    ok $row->{cancelled_at}, 'cancelled_at is set';
};

subtest 'cancel already cancelled token' => sub {
    my $tok = $auth->create_token(note => 'double cancel');
    $auth->cancel_token($tok->{id});
    my $res = $auth->cancel_token($tok->{id});
    ok $res->{error}, 'second cancel returns error';
};

subtest 'record token use' => sub {
    my $tok = $auth->create_token(note => 'counter test');
    is $tok->{use_count}, 0, 'starts at 0';

    $auth->record_token_use($tok->{id});
    $auth->record_token_use($tok->{id});

    my $updated = $auth->get_token($tok->{id});
    is $updated->{use_count}, 2, 'use_count incremented to 2';
    ok $updated->{last_used_at}, 'last_used_at set';
};

subtest 'validate_token rejects undef and empty' => sub {
    ok !$auth->validate_token(undef), 'undef rejected';
    ok !$auth->validate_token(''), 'empty string rejected';
    ok !$auth->validate_token('not-a-real-token'), 'unknown token rejected';
};

done_testing;
