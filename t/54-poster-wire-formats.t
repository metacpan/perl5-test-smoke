use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";
use lib "$FindBin::Bin/lib";

use TestApp;
use Mojo::File  qw(path);
use URI::Escape qw(uri_escape);

# End-to-end ingest tests that mimic the byte-for-byte HTTP requests
# emitted by every Test::Smoke Poster shipped in legacy/Test-Smoke.
#
# Wire formats observed in legacy/Test-Smoke:
#
#   pre-2022-10-20  Form-encoded `json=<CGI::Util::escape($json)>` with
#                   Content-Type: application/x-www-form-urlencoded.
#                   ~9 years (2013-2022), all releases <= 1.80.
#
#   2022-10-20+     Form-encoded `json=<URI::Escape::uri_escape($json)>`,
#                   same Content-Type. Used by `_post_data` in HTTP_Tiny,
#                   Curl, and LWP_UserAgent. Test::Smoke 1.81.
#
#   2023-10-25+     Modern JSON body sprintf q/{"report_data": %s}/, $json
#                   with Content-Type: application/json. Used by
#                   `_post_data_api` (auto-selected when smokedb_url
#                   contains "/api/"). Test::Smoke 1.81_01 / 1.82+.
#
# The two form-encoded variants produce equivalent percent-encoded bodies
# for most JSON content, but they differ on a few characters (spaces,
# tildes). Compact JSON-encoded reports have no whitespace so the practical
# difference is small, but we exercise both anyway.
#
# Each scenario:
#   * POSTs the exact body + headers a real Poster would send
#   * Routes to one of /api/report, /api/old_format_reports, /report
#   * Asserts 200 + id, then re-queries the DB and disk to confirm
#     the report and its on-disk artefacts landed correctly.

# Same percent-encoding rules CGI::Util::escape uses (as it shipped in
# Test::Smoke <= 1.80): every byte that is not [A-Za-z0-9_.~-] becomes
# %XX (uppercase). No '+' for space.
sub cgi_util_escape ($s) {
    my $bytes = $s;
    utf8::encode($bytes) if utf8::is_utf8($bytes);
    $bytes =~ s/([^A-Za-z0-9_.~\-])/sprintf '%%%02X', ord $1/ge;
    return $bytes;
}

# Modern Test::Smoke 1.81_01+: the inner $json is concatenated raw, NOT
# JSON-re-encoded. This matches sprintf qq/{"report_data": %s}/, $json.
sub modern_json_body ($raw_json) {
    return sprintf qq/{"report_data": %s}/, $raw_json;
}

sub form_body_uri_escape ($raw_json) { 'json=' . uri_escape($raw_json) }
sub form_body_cgi_util   ($raw_json) { 'json=' . cgi_util_escape($raw_json) }

my $TS_VERSION   = '1.87';
sub ua ($poster) { "Test::Smoke/$TS_VERSION (Test::Smoke::Poster::$poster)" }

# Slurp the fixture as raw bytes -- this is what get_json() returns to
# the Poster (the file content of mktest.jsn), and what gets concatenated
# into the wire body.
my $RAW_JSON = path("$FindBin::Bin/data/idefix-gff5bbe677.jsn")->slurp;

my @scenarios = (
    # --- Modern JSON wire format (Test::Smoke 1.81_01+ / 1.82+ default) ---
    {
        name => 'HTTP_Tiny _post_data_api -> /api/report',
        url  => '/api/report',
        ct   => 'application/json',
        ua   => ua('HTTP_Tiny'),
        body => modern_json_body($RAW_JSON),
    },
    {
        name => 'Curl _post_data_api -> /api/report',
        url  => '/api/report',
        ct   => 'application/json',
        ua   => ua('Curl'),
        body => modern_json_body($RAW_JSON),
    },
    {
        name => 'LWP_UserAgent _post_data_api -> /api/report',
        url  => '/api/report',
        ct   => 'application/json',
        ua   => ua('LWP_UserAgent'),
        body => modern_json_body($RAW_JSON),
    },
    # Cross-format: smoker upgraded the URL but kept a pre-1.81_01 client,
    # so the body is still legacy form-encoded but the URL is modern.
    {
        name => 'legacy form (URI::Escape) cross-format -> /api/report',
        url  => '/api/report',
        ct   => 'application/x-www-form-urlencoded',
        ua   => ua('HTTP_Tiny'),
        body => form_body_uri_escape($RAW_JSON),
    },

    # --- Legacy form-encoded (URI::Escape, 2022-10 - 2024-04 / 1.81) ---
    {
        name => 'legacy URI::Escape -> /report',
        url  => '/report',
        ct   => 'application/x-www-form-urlencoded',
        ua   => ua('HTTP_Tiny'),
        body => form_body_uri_escape($RAW_JSON),
    },
    {
        name => 'legacy URI::Escape -> /api/old_format_reports',
        url  => '/api/old_format_reports',
        ct   => 'application/x-www-form-urlencoded',
        ua   => ua('Curl'),
        body => form_body_uri_escape($RAW_JSON),
    },

    # --- Legacy form-encoded (CGI::Util, pre-2022-10, Test::Smoke <= 1.80) ---
    {
        name => 'legacy CGI::Util -> /report',
        url  => '/report',
        ct   => 'application/x-www-form-urlencoded',
        ua   => ua('HTTP_Tiny'),
        body => form_body_cgi_util($RAW_JSON),
    },
    {
        name => 'legacy CGI::Util -> /api/old_format_reports',
        url  => '/api/old_format_reports',
        ct   => 'application/x-www-form-urlencoded',
        ua   => ua('LWP_UserAgent'),
        body => form_body_cgi_util($RAW_JSON),
    },
);

for my $sc (@scenarios) {
    subtest $sc->{name} => sub {
        TestApp::reset_db();
        my $h = TestApp->new;
        my $t = $h->t;

        $t->post_ok(
            $sc->{url} => {
                'Content-Type' => $sc->{ct},
                'User-Agent'   => $sc->{ua},
            } => $sc->{body}
        )->status_is(200)->json_has('/id');

        my $rid = $t->tx->res->json('/id');
        ok $rid, "got report id ($rid)";

        my $row = $h->app->sqlite->db->query(
            'SELECT hostname, summary, plevel, report_hash, git_describe '
                . 'FROM report WHERE id = ?',
            $rid,
        )->hash;
        ok $row, 'report row exists';
        is $row->{hostname}, 'idefix', 'hostname stored from sysinfo';
        is $row->{summary},  'PASS',   'summary stored';
        like $row->{plevel},      qr/^5\./,           'plevel computed';
        like $row->{report_hash}, qr/^[a-f0-9]{32}$/, 'report_hash is md5_hex';
        like $row->{git_describe}, qr/[a-f0-9]/, 'git_describe stored';

        my $manifest = $h->app->report_files->read($rid, 'manifest_msgs');
        like $manifest, qr/MANIFEST did not declare/,
            'manifest_msgs round-trips through xz file on disk';

        # configs / results / failures actually got linked.
        my ($cfg_count) = $h->app->sqlite->db->query(
            'SELECT COUNT(*) FROM config WHERE report_id = ?', $rid
        )->array->@*;
        ok $cfg_count >= 1, "configs inserted ($cfg_count)";
    };
}

done_testing;
