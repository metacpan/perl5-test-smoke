use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use TestApp;
use Mojo::JSON         qw(encode_json);
use IO::Compress::Gzip qw(gzip $GzipError);

my $h = TestApp->new;
my $t = $h->t;

my $json_body = encode_json({ report_data => $h->fixture('idefix-gff5bbe677.jsn') });

my $gz;
gzip(\$json_body => \$gz)
    or die "gzip failed: $GzipError";

$t->post_ok('/api/report' =>
    {
        'Content-Type'     => 'application/json',
        'Content-Encoding' => 'gzip',
    } =>
    $gz
)->status_is(200)->json_has('/id');

# Bad gzip body should 400
$t->post_ok('/api/report' =>
    {
        'Content-Type'     => 'application/json',
        'Content-Encoding' => 'gzip',
    } =>
    "not actually gzipped"
)->status_is(400);

# --- Streaming decompression (default 10 MB limit) ---

# Default max_decompressed_size (10 MB) should handle normal payloads
# without 413.  The body is still invalid JSON / not a real report,
# so the controller rejects it -- but the hook must let it through.
my $big_body = 'x' x 200_000;
my $gz_big;
gzip(\$big_body => \$gz_big)
    or die "gzip big failed: $GzipError";

$t->post_ok('/api/report' =>
    {
        'Content-Type'     => 'application/json',
        'Content-Encoding' => 'gzip',
    } =>
    $gz_big
)->status_isnt(413);

# --- Explicit decompressed-size limit (override default) ---

$h->app->config->{max_decompressed_size} = 1024;

my $bomb_body = 'x' x 2048;
my $gz_bomb;
gzip(\$bomb_body => \$gz_bomb)
    or die "gzip bomb failed: $GzipError";

$t->post_ok('/api/report' =>
    {
        'Content-Type'     => 'application/json',
        'Content-Encoding' => 'gzip',
    } =>
    $gz_bomb
)->status_is(413)->json_is('/error' => 'Decompressed body too large');

# A payload under the limit should still decompress fine
my $small_body = '{"not":"valid report but small"}';
my $gz_small;
gzip(\$small_body => \$gz_small)
    or die "gzip small failed: $GzipError";

$t->post_ok('/api/report' =>
    {
        'Content-Type'     => 'application/json',
        'Content-Encoding' => 'gzip',
    } =>
    $gz_small
)->status_isnt(413);

# Restore default so subsequent tests are not affected
delete $h->app->config->{max_decompressed_size};

done_testing;
