use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use TestApp;
use CoreSmoke::Model::ReportFiles;

my $h   = TestApp->new;
my $app = $h->app;
my $rf  = $app->report_files;

my $hash = 'deadbeefcafef00d' . ('0' x 16);
my $payload = "Line 1\nLine 2\nLine \xff\x00\x7f end\n";

$rf->write($hash, { log_file => $payload, manifest_msgs => 'tiny' });

# read_by_hash should round-trip
is $rf->read_by_hash($hash, 'log_file'),     $payload, 'log_file round-trip';
is $rf->read_by_hash($hash, 'manifest_msgs'), 'tiny',  'manifest_msgs round-trip';

# Missing files return undef, not exceptions
is $rf->read_by_hash($hash, 'out_file'),     undef, 'missing field returns undef';
is $rf->read_by_hash('0' x 32, 'log_file'),  undef, 'missing hash returns undef';

# Path is sharded as documented
is $rf->path_for($hash),
   $app->config->{reports_dir} . "/de/ad/be/$hash",
   'sharded path layout';

# Unknown field name silently no-ops
$rf->write($hash, { not_a_field => 'whatever' });
is $rf->read_by_hash($hash, 'not_a_field'), undef, 'unknown field not written';

# has_file: true for written fields, false for missing
is $rf->has_file($hash, 'log_file'),      1, 'has_file true for existing file';
is $rf->has_file($hash, 'manifest_msgs'), 1, 'has_file true for another existing file';
is $rf->has_file($hash, 'out_file'),      0, 'has_file false for unwritten field';
is $rf->has_file('0' x 32, 'log_file'),   0, 'has_file false for missing hash';
is $rf->has_file($hash, 'not_a_field'), undef, 'has_file undef for unknown field';

done_testing;
