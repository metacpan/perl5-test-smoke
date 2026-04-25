package TestApp;
use v5.42;
use warnings;
use experimental qw(signatures);

use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../../local/lib/perl5";

use Test::Mojo;
use File::Path qw(remove_tree);

my $T         = $FindBin::Bin;
my $TEST_DB   = "$T/test.db";
my $REPORTS   = "$T/data/reports-tmp";

sub new ($class) {
    $ENV{MOJO_MODE}         = 'test';
    $ENV{SMOKE_DB_PATH}     = $TEST_DB;
    $ENV{SMOKE_REPORTS_DIR} = $REPORTS;

    reset_db();

    my $t = Test::Mojo->new('CoreSmoke::App');
    return bless { t => $t }, $class;
}

sub reset_db {
    unlink $TEST_DB, "$TEST_DB-wal", "$TEST_DB-shm";
    remove_tree($REPORTS) if -d $REPORTS;
}

sub t   ($self) { $self->{t} }
sub app ($self) { $self->{t}->app }

1;
