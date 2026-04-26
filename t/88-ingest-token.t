use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use TestApp;
use Mojo::JSON qw(encode_json);

my $h = TestApp->new;
my $t = $h->t;

# Create a valid API token
my $tok    = $h->app->auth->create_token(note => 'test-smoker', email => 'test@example.com');
my $token  = $tok->{token};
my $tok_id = $tok->{id};

# Create a second token and cancel it
my $cancelled = $h->app->auth->create_token(note => 'cancelled');
$h->app->auth->cancel_token($cancelled->{id});
my $cancelled_token = $cancelled->{token};

# Load the fixture for repeated use
my $fixture = $h->fixture('idefix-gff5bbe677.jsn');

# Helper: tweak the fixture so each ingest is unique (avoid duplicate rejection)
my $counter = 0;
sub unique_fixture {
    my %copy = %$fixture;
    my %sys  = %{ $copy{sysinfo} // {} };
    $sys{hostname} = "testhost-" . ++$counter;
    $copy{sysinfo} = \%sys;
    return \%copy;
}

subtest 'ingest without token: api_token_id is NULL' => sub {
    my $data = unique_fixture();
    my $resp = $t->post_ok('/api/report', json => { report_data => $data })
        ->status_is(200)
        ->tx->res->json;
    ok $resp->{id}, 'got report id';

    my $row = $h->app->sqlite->db->query(
        "SELECT api_token_id FROM report WHERE id = ?", $resp->{id}
    )->hash;
    is $row->{api_token_id}, undef, 'api_token_id is NULL without token';
};

subtest 'ingest with valid Bearer token: api_token_id set' => sub {
    my $data = unique_fixture();
    $t->post_ok('/api/report',
        { Authorization => "Bearer $token" },
        json => { report_data => $data },
    )->status_is(200);

    my $rid = $t->tx->res->json->{id};
    ok $rid, 'got report id';

    my $row = $h->app->sqlite->db->query(
        "SELECT api_token_id FROM report WHERE id = ?", $rid
    )->hash;
    is $row->{api_token_id}, $tok_id, 'api_token_id matches token';

    my $updated = $h->app->auth->get_token($tok_id);
    ok $updated->{use_count} >= 1, 'use_count incremented';
    ok $updated->{last_used_at}, 'last_used_at set';
};

subtest 'ingest with invalid token: succeeds but api_token_id is NULL' => sub {
    my $data = unique_fixture();
    $t->post_ok('/api/report',
        { Authorization => 'Bearer not-a-real-token' },
        json => { report_data => $data },
    )->status_is(200);

    my $rid = $t->tx->res->json->{id};
    my $row = $h->app->sqlite->db->query(
        "SELECT api_token_id FROM report WHERE id = ?", $rid
    )->hash;
    is $row->{api_token_id}, undef, 'invalid token -> NULL api_token_id';
};

subtest 'ingest with cancelled token: succeeds but api_token_id is NULL' => sub {
    my $data = unique_fixture();
    $t->post_ok('/api/report',
        { Authorization => "Bearer $cancelled_token" },
        json => { report_data => $data },
    )->status_is(200);

    my $rid = $t->tx->res->json->{id};
    my $row = $h->app->sqlite->db->query(
        "SELECT api_token_id FROM report WHERE id = ?", $rid
    )->hash;
    is $row->{api_token_id}, undef, 'cancelled token -> NULL api_token_id';
};

subtest 'JSONRPC post_report with valid token' => sub {
    my $data = unique_fixture();
    my $rpc_body = encode_json({
        jsonrpc => '2.0',
        id      => 1,
        method  => 'post_report',
        params  => { report_data => $data },
    });

    $t->post_ok('/api',
        { Authorization => "Bearer $token", 'Content-Type' => 'application/json' },
        $rpc_body,
    )->status_is(200);

    my $result = $t->tx->res->json->{result};
    ok $result->{id}, 'JSONRPC got report id';

    my $row = $h->app->sqlite->db->query(
        "SELECT api_token_id FROM report WHERE id = ?", $result->{id}
    )->hash;
    is $row->{api_token_id}, $tok_id, 'JSONRPC token stored';
};

subtest 'JSONRPC post_report without token' => sub {
    my $data = unique_fixture();
    my $rpc_body = encode_json({
        jsonrpc => '2.0',
        id      => 2,
        method  => 'post_report',
        params  => { report_data => $data },
    });

    $t->post_ok('/api',
        { 'Content-Type' => 'application/json' },
        $rpc_body,
    )->status_is(200);

    my $result = $t->tx->res->json->{result};
    ok $result->{id}, 'JSONRPC got report id';

    my $row = $h->app->sqlite->db->query(
        "SELECT api_token_id FROM report WHERE id = ?", $result->{id}
    )->hash;
    is $row->{api_token_id}, undef, 'JSONRPC without token -> NULL';
};

done_testing;
