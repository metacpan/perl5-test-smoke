use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use File::Temp qw(tmpnam);

my $db_path = tmpnam() . '.db';

my $script = "$FindBin::Bin/../script/create-admin";

# Create a user
my $out = `MOJO_MODE=test SMOKE_DB_PATH=$db_path $^X $script --username testadmin --password s3cret 2>&1`;
is $?, 0, 'script exits 0 on success';
like $out, qr/created successfully/, 'success message printed';

# Verify the user exists in the DB and can be authenticated
require CoreSmoke::Model::DB;
require CoreSmoke::Model::Auth;
my $db = CoreSmoke::Model::DB->new(
    path           => $db_path,
    migrations_sql => "$FindBin::Bin/../lib/CoreSmoke/Schema/migrations.sql",
);
my $auth = CoreSmoke::Model::Auth->new(
    sqlite => $db,
    pepper => 'test-pepper',
);
ok $auth->verify_user('testadmin', 's3cret'), 'created user verifies';

# Duplicate user
$out = `MOJO_MODE=test SMOKE_DB_PATH=$db_path $^X $script --username testadmin --password other 2>&1`;
isnt $?, 0, 'duplicate exits non-zero';
like $out, qr/already exists/i, 'error message for duplicate';

# Missing args
$out = `MOJO_MODE=test SMOKE_DB_PATH=$db_path $^X $script 2>&1`;
isnt $?, 0, 'missing args exits non-zero';

# Cleanup
unlink $db_path, "$db_path-wal", "$db_path-shm";

done_testing;
