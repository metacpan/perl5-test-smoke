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

done_testing;
