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

# --- Non-integer rid values ---
for my $route (qw(/file/log_file /file/out_file)) {
    $t->get_ok("$route/abc")->status_is(404);
    $t->get_ok("$route/foo.bar")->status_is(404);
}

# --- Path traversal attempts ---
$t->get_ok('/file/log_file/../../etc/passwd')->status_is(404);
$t->get_ok('/file/out_file/../../etc/passwd')->status_is(404);

# URL-encoded traversal
$t->get_ok('/file/log_file/1%2F..%2F..%2Fetc%2Fpasswd')->status_is(404);
$t->get_ok('/file/out_file/1%2F..%2F..%2Fetc%2Fpasswd')->status_is(404);

# --- Negative and zero ---
$t->get_ok('/file/log_file/-1')->status_is(404);
$t->get_ok('/file/out_file/-1')->status_is(404);
$t->get_ok('/file/log_file/0') ->status_is(404);
$t->get_ok('/file/out_file/0') ->status_is(404);

# --- Very large number (no matching row) ---
$t->get_ok('/file/log_file/999999999')->status_is(404);
$t->get_ok('/file/out_file/999999999')->status_is(404);

# --- SQL injection in rid (parameterized queries make this safe) ---
$t->get_ok('/file/log_file/1 OR 1=1')->status_is(404);
$t->get_ok('/file/out_file/1 OR 1=1')->status_is(404);

done_testing;
