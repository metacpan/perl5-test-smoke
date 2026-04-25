package CoreSmoke::App;
use v5.42;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious', -signatures;

use CoreSmoke::Model::DB;
use CoreSmoke::Model::Reports;
use CoreSmoke::Model::Ingest;
use CoreSmoke::Model::ReportFiles;

sub startup ($self) {
    $self->plugin('Config' => { file => $self->_config_file });

    $self->routes->namespaces(['CoreSmoke::Controller']);

    my $cfg = $self->config;
    $self->log->level($cfg->{log_level} // 'info');

    my $home = $self->home;
    my $db_path     = $ENV{SMOKE_DB_PATH}     // $cfg->{db_path}     // $home->child('data/smoke.db');
    my $reports_dir = $ENV{SMOKE_REPORTS_DIR} // $cfg->{reports_dir} // $home->child('data/reports');

    $self->max_request_size(16 * 1024 * 1024);

    my $sqlite = CoreSmoke::Model::DB->new(
        path           => $db_path,
        migrations_sql => $home->child('lib/CoreSmoke/Schema/migrations.sql'),
    );
    $sqlite->migrate;

    $self->helper(sqlite       => sub ($c) { $sqlite });
    $self->helper(reports      => sub ($c) { state $r = CoreSmoke::Model::Reports->new(sqlite => $sqlite) });
    $self->helper(report_files => sub ($c) { state $f = CoreSmoke::Model::ReportFiles->new(root => $reports_dir, sqlite => $sqlite) });
    $self->helper(ingest       => sub ($c) {
        state $i = CoreSmoke::Model::Ingest->new(
            sqlite       => $sqlite,
            report_files => $c->app->report_files,
        );
    });

    $self->hook(before_dispatch => sub ($c) {
        my $enc = $c->req->headers->header('Content-Encoding') // '';
        return unless $enc eq 'gzip';
        require IO::Uncompress::Gunzip;
        my $body = $c->req->body;
        my $out;
        unless (IO::Uncompress::Gunzip::gunzip(\$body => \$out)) {
            return $c->render(status => 400, json => { error => 'Bad gzip body' });
        }
        $c->req->body($out);
        $c->req->headers->remove('Content-Encoding');
    });

    $self->hook(after_dispatch => sub ($c) {
        my $origin = $c->app->config->{cors_allow_origin} // '*';
        $c->res->headers->access_control_allow_origin($origin);
        $c->res->headers->header('Access-Control-Allow-Methods' => 'GET, POST, OPTIONS');
    });

    my $r = $self->routes;

    # Health checks
    $r->get('/healthz')->to('System#healthz');
    $r->get('/readyz') ->to('System#readyz');

    # /system REST
    $r->get('/system/ping')   ->to('System#ping');
    $r->get('/system/version')->to('System#version');
    $r->get('/system/status') ->to('System#status');
    $r->get('/system/methods')->to('System#list_methods');
    $r->get('/system/methods/:plugin')->to('System#list_methods');

    # /api REST
    $r->get('/api/version')                ->to('Api#version');
    $r->get('/api/latest')                 ->to('Api#latest');
    $r->get('/api/full_report_data/:rid')  ->to('Api#full_report_data');
    $r->get('/api/report_data/:rid')       ->to('Api#report_data');
    $r->get('/api/logfile/:rid')           ->to('Api#logfile');
    $r->get('/api/outfile/:rid')           ->to('Api#outfile');
    $r->get('/api/matrix')                 ->to('Api#matrix');
    $r->get('/api/submatrix')              ->to('Api#submatrix');
    $r->get('/api/searchparameters')       ->to('Api#searchparameters');
    $r->any([qw(GET POST)] => '/api/searchresults')->to('Api#searchresults');
    $r->get('/api/reports_from_id/:rid')   ->to('Api#reports_from_id');
    $r->get('/api/reports_from_date/:epoch')->to('Api#reports_from_epoch');

    # OpenAPI
    $r->get('/api/openapi/web.json')->to('Api#openapi_json');
    $r->get('/api/openapi/web.yaml')->to('Api#openapi_yaml');
    $r->get('/api/openapi/web')     ->to('Api#openapi_text');

    # Ingest
    $r->post('/api/report')             ->to('Ingest#post_report');
    $r->post('/api/old_format_reports') ->to('Ingest#post_old_format_report');
    $r->post('/report')                 ->to('Ingest#post_old_format_report');

    # JSONRPC
    $r->post('/api')   ->to('JsonRpc#dispatch');
    $r->post('/system')->to('JsonRpc#dispatch');

    # Web (server-rendered HTML)
    $r->get('/')      ->to('Web#latest');
    $r->get('/latest')->to('Web#latest');
    $r->get('/search')->to('Web#search');
    $r->get('/matrix')->to('Web#matrix');
    $r->get('/submatrix')->to('Web#submatrix');
    $r->get('/about') ->to('Web#about');
    $r->get('/report/:rid')          ->to('Web#full_report');
    $r->get('/file/log_file/:rid')   ->to('Web#log_file');
    $r->get('/file/out_file/:rid')   ->to('Web#out_file');

    # 404 fallback
    $r->any('/*whatever' => { whatever => '' })->to('Web#not_found');
}

sub _config_file ($self) {
    return $ENV{MOJO_CONFIG} if $ENV{MOJO_CONFIG};
    my $mode = $self->mode;
    my $home = $self->home;
    my $mode_file = $home->child("etc/coresmoke.$mode.conf");
    return "$mode_file" if -e $mode_file;
    return $home->child('etc/coresmoke.conf')->to_string;
}

1;
