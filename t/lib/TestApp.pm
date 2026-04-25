package TestApp;
use v5.42;
use warnings;
use experimental qw(signatures);

use FindBin;
use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/../../local/lib/perl5";

use Test::Mojo;
use Mojo::JSON  qw(decode_json);
use Mojo::File  qw();
use File::Path  qw(remove_tree);

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

sub fixture ($self, $name) {
    my $path = "$T/data/$name";
    return decode_json(Mojo::File->new($path)->slurp);
}

sub ingest_fixture ($self, $name) {
    my $body = $self->fixture($name);
    return $self->{t}
        ->post_ok('/api/report', json => { report_data => $body })
        ->status_is(200)
        ->tx->res->json;
}

1;
