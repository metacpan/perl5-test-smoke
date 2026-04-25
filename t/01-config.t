use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use TestApp;

my $h   = TestApp->new;
my $app = $h->app;

# Config loaded
ok $app->config->{db_path},     'db_path config present';
ok $app->config->{reports_dir}, 'reports_dir config present';
is $app->config->{cors_allow_origin}, '*', 'CORS wildcard default';

# Migration applied
my $tables = $app->sqlite->db->query(
    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
)->arrays->to_array;
my @names = map { $_->[0] } @$tables;
my %got = map { $_ => 1 } @names;
for my $expected (qw(report config result failure failures_for_env smoke_config tsgateway_config)) {
    ok $got{$expected}, "table $expected exists";
}

# dbversion = 4
my $row = $app->sqlite->db->query(
    "SELECT value FROM tsgateway_config WHERE name = 'dbversion'"
)->hash;
is $row->{value}, '4', 'dbversion is 4';

# Pragmas
my $pragmas = $app->sqlite->pragma_check;
is $pragmas->{foreign_keys}, 1,     'foreign_keys = 1';
is $pragmas->{journal_mode}, 'wal', 'journal_mode = wal';

# No BLOB columns on report
my $cols = $app->sqlite->db->query("PRAGMA table_info(report)")->hashes->to_array;
my @blob = grep { ($_->{type} // '') eq 'BLOB' } @$cols;
is scalar(@blob), 0, 'report table has no BLOB columns';
my %has = map { $_->{name} => 1 } @$cols;
ok $has{report_hash}, 'report_hash column present';

done_testing;
