# 04 — JSONRPC 2.0 dispatcher

## Goal

Expose every method that REST exposes (plan 03) as a JSONRPC 2.0 method at `POST /api` (and `POST /system` for system methods), preserving legacy method names. **Built in the same milestone as the REST controllers (plan 03)** since they share the registry and DAO helpers.

## Why an in-app dispatcher

The legacy `config.yml` shows the JSONRPC and RESTish dispatchers are pure config that map method names → controller actions. The work is dispatching, not framework integration. A small dispatcher in `Controller::JsonRpc` keeps both protocols backed by the same DAO with no CPAN plugin to track.

## Method registry

Build a static registry constructed at startup; same names as the legacy `config.yml`:

```perl
# lib/CoreSmoke/JsonRpc/Methods.pm
package CoreSmoke::JsonRpc::Methods;
use v5.42;
use experimental qw(signatures);

our %METHODS = (
    # /system plugin
    ping             => { plugin => 'system', call => sub ($c, $params) { 'pong' } },
    status           => { plugin => 'system', call => \&_status },
    version          => { plugin => 'system', call => \&_system_version },
    list_methods     => { plugin => 'system', call => \&_list_methods },

    # /api plugin
    latest           => { plugin => 'api', call => sub ($c, $p) { $c->app->reports->latest } },
    full_report_data => { plugin => 'api', call => sub ($c, $p) { $c->app->reports->full_report_data($p->{rid}) // { error => 'Report not found.' } } },
    report_data      => { plugin => 'api', call => sub ($c, $p) { $c->app->reports->report_data($p->{rid})      // { error => 'Report not found.' } } },
    logfile          => { plugin => 'api', call => sub ($c, $p) {
        my $bytes = $c->app->report_files->read($p->{rid}, 'log_file');
        return defined $bytes ? { file => $bytes } : { error => 'Log file not found.' };
    } },
    outfile          => { plugin => 'api', call => sub ($c, $p) {
        my $bytes = $c->app->report_files->read($p->{rid}, 'out_file');
        return defined $bytes ? { file => $bytes } : { error => 'Out file not found.' };
    } },
    matrix           => { plugin => 'api', call => sub ($c, $p) { $c->app->reports->matrix } },
    submatrix        => { plugin => 'api', call => sub ($c, $p) { $c->app->reports->submatrix($p->{test}, $p->{pversion}) } },
    searchparameters => { plugin => 'api', call => sub ($c, $p) { $c->app->reports->searchparameters } },
    searchresults    => { plugin => 'api', call => sub ($c, $p) { $c->app->reports->searchresults($p) } },
    post_report      => { plugin => 'api', call => sub ($c, $p) { $c->app->ingest->post_report($p->{report_data}) } },
    reports_from_id  => { plugin => 'api', call => sub ($c, $p) { $c->app->reports->reports_from_id($p->{rid}, $p->{limit} // 100) } },
    reports_from_date => { plugin => 'api', call => sub ($c, $p) { $c->app->reports->reports_from_epoch($p->{epoch}) } },
);

sub all { \%METHODS }
1;
```

Note: REST controllers (plan 03) and the JSONRPC dispatcher delegate to the **same** `$c->app->reports->*` / `$c->app->ingest->*` / `$c->app->report_files->*` helpers. There is one DAO; the two protocols are thin shells.

## Dispatcher

```perl
package CoreSmoke::Controller::JsonRpc;
use v5.42;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;
use CoreSmoke::JsonRpc::Methods;

sub dispatch ($c) {
    my $req = $c->req->json
        // return _reply($c, undef, _err(-32700, 'Parse error.'));

    return _batch($c, $req)  if ref $req eq 'ARRAY';
    return _single($c, $req);
}

sub _single ($c, $req) {
    my $id     = $req->{id};
    my $method = $req->{method} // '';
    my $params = $req->{params} // {};

    my $entry = CoreSmoke::JsonRpc::Methods->all->{$method};
    return _reply($c, $id, _err(-32601, "Method '$method' not found.")) unless $entry;

    my $result = eval { $entry->{call}->($c, $params) };
    if (my $e = $@) {
        $c->app->log->error("JSONRPC $method failed: $e");
        return _reply($c, $id, _err(-32603, "$e"));
    }
    return _reply($c, $id, { result => $result });
}

sub _batch ($c, $reqs) {
    my @out = map { _single_payload($c, $_) } @$reqs;
    return $c->render(json => \@out);
}

sub _reply ($c, $id, $payload) {
    return $c->render(json => {
        jsonrpc => '2.0',
        id      => $id,
        %$payload,
    });
}

sub _err ($code, $message, $data = undef) {
    my %err = (code => $code, message => $message);
    $err{data} = $data if defined $data;
    return { error => \%err };
}

1;
```

## Routes

In `App::startup`:

```perl
$r->any([qw(POST)] => '/api')->to('JsonRpc#dispatch');
$r->any([qw(POST)] => '/system')->to('JsonRpc#dispatch');
```

## Method/plugin filtering

`list_methods` is invoked as either GET REST (`/system/methods` / `/system/methods/:plugin`) or JSONRPC (`{"method":"list_methods", "params":{"plugin":"api"}}`). Implementation reads the registry and returns method names, optionally filtered by plugin.

## Error mapping

| Condition | Code |
|----------|------|
| Body not JSON | -32700 (Parse error) |
| Missing/wrong shape | -32600 (Invalid Request) |
| Unknown method | -32601 (Method not found) |
| Invalid params | -32602 (Invalid params) |
| DAO/internal | -32603 (Internal error) |

The legacy library returned application-level errors (e.g. `"Report not found."`) inside the `result` field on the REST side and as JSONRPC errors on the JSONRPC side — preserve this asymmetry by emitting `_err` from the dispatcher only for transport errors. Application errors are returned as `{ error => "..." }` inside `result` to match legacy clients.

## Critical files to read

- `legacy/api/config.yml`  (method-name registry; do not rename anything)
- `legacy/api/lib/CoreSmokeDB/API/Web.pm`  (each `rpc_*` sub's return shape)
- Dancer2 RPC plugin behavior:
  - `legacy/api/Makefile.PL` — `Dancer2::Plugin::RPC` `>= 2.02`
  - `Dancer2::RPCPlugin::DispatchFromConfig` (CPAN docs)

## Verification

1. `t/40-jsonrpc.t` — for each method in the registry, fire a JSONRPC POST with valid params and assert the result equals the equivalent REST response (parity tests).
2. Batch request test: send `[{method:"ping",id:1},{method:"version",id:2}]`, expect array response with both ids.
3. Error tests: unknown method → -32601; malformed body → -32700; valid envelope but invalid params → -32602.
4. `list_methods` returns the full registry; with `params.plugin = "system"`, returns only system methods.
5. `t/41-jsonrpc-errors.t` covers transport errors and batch responses.
