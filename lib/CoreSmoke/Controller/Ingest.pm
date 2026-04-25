package CoreSmoke::Controller::Ingest;
use v5.42;
use warnings;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;

use Mojo::JSON qw(decode_json);

# POST /api/report -- modern Test::Smoke clients (>= 1.81).
# Body: { "report_data": { ... } }, optionally Content-Encoding: gzip
# (decoded by App::startup before_dispatch hook).
sub post_report ($c) {
    my $payload = $c->req->json
        // return $c->render(status => 400, json => { error => 'Invalid JSON.' });
    my $data = $payload->{report_data}
        // return $c->render(status => 422, json => { error => 'Missing report_data.' });
    my $result = $c->app->ingest->post_report($data);
    return $c->render(status => 409, json => $result) if $result->{error};
    return $c->render(json => $result);
}

# POST /api/old_format_reports and POST /report -- pre-1.81 Test::Smoke
# clients send application/x-www-form-urlencoded with a single param `json`
# whose value is the percent-encoded JSON report (NOT nested under
# `report_data`).
sub post_old_format_report ($c) {
    my $raw = $c->req->param('json')
        // return $c->render(status => 422, json => { error => 'Missing json param.' });
    my $data = eval { decode_json($raw) };
    return $c->render(status => 400, json => { error => "Bad JSON: $@" }) if $@;
    my $result = $c->app->ingest->post_report($data);
    return $c->render(status => 409, json => $result) if $result->{error};
    return $c->render(json => $result);
}

1;
