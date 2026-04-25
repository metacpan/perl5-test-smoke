package CoreSmoke::Controller::Web;
use v5.42;
use warnings;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub _is_htmx ($c) {
    return ($c->req->headers->header('HX-Request') // '') eq 'true';
}

sub latest ($c) {
    my $page = int($c->param('page') || 1);
    my $rpp  = int($c->param('reports_per_page') || 25);
    my $data = $c->app->reports->latest({ page => $page, reports_per_page => $rpp });

    my $tmpl = _is_htmx($c) ? 'web/_reports_rows' : 'web/latest';
    return $c->render(template => $tmpl,
        path             => '/latest',
        reports          => $data->{reports},
        report_count     => $data->{report_count},
        page             => $page,
        reports_per_page => $rpp,
        latest_plevel    => $data->{latest_plevel},
    );
}

sub search ($c) {
    my %filter;
    for my $key (qw(
        selected_arch selected_osnm selected_osvs selected_host
        selected_comp selected_cver selected_perl selected_branch
        andnotsel_arch andnotsel_osnm andnotsel_osvs andnotsel_host
        andnotsel_comp andnotsel_cver
        page reports_per_page
    )) {
        my $v = $c->param($key);
        $filter{$key} = $v if defined $v;
    }
    my $page    = int($filter{page}             || 1);
    my $rpp     = int($filter{reports_per_page} || 25);

    # Resolve `selected_perl=latest` once for the whole request via the
    # RPM-style version sort, then feed the same concrete perl_id into
    # both the cascading-dropdown query and the result query. The
    # template still gets the original \%filter so the dropdown renders
    # with `latest` selected.
    my %effective = %filter;
    if (($effective{selected_perl} // '') eq 'latest') {
        $effective{selected_perl} = $c->app->reports->latest_perl_id // 'all';
    }
    my $available = $c->app->reports->available_filter_values(\%effective);
    my $results   = $c->app->reports->searchresults({ %effective, page => $page, reports_per_page => $rpp });

    # Form changes (HTMX) re-render the whole search region: the form
    # (so the cascading dropdowns refresh against the new filter) AND
    # the results table. The form's hx-target is #search-region with
    # outerHTML swap, so this fragment replaces itself in place.
    #
    # Infinite-scroll triggers from inside #report-rows have their own
    # hx-target=this and hx-swap=outerHTML, so they pull only the rows
    # fragment. We distinguish via HX-Trigger-Name: form submissions
    # set it to the input name; the load-more <tr> doesn't have a
    # name. Easier: distinguish by HX-Trigger ID -- the load-more row
    # has a class but no id; the form has id="search-form".
    my $is_form_change = _is_htmx($c)
        && (($c->req->headers->header('HX-Trigger') // '') eq 'search-form');

    if (_is_htmx($c) && !$is_form_change) {
        # Infinite-scroll request: only the rows fragment.
        return $c->render(template => 'web/_reports_rows',
            path             => '/search',
            reports          => $results->{reports},
            report_count     => $results->{report_count},
            page             => $page,
            reports_per_page => $rpp,
            filter           => \%filter,
        );
    }

    my $template = _is_htmx($c) ? 'web/_search_region' : 'web/search';
    return $c->render(template => $template,
        available => $available,
        filter    => \%filter,
        results   => $results,
        page      => $page,
        reports_per_page => $rpp,
    );
}

sub matrix ($c) {
    my $data = $c->app->reports->matrix;
    return $c->render(template => 'web/matrix', %$data);
}

sub submatrix ($c) {
    my $test     = $c->param('test');
    my $pversion = $c->param('pversion');
    my $reports  = defined $test
        ? $c->app->reports->submatrix($test, $pversion)
        : [];
    return $c->render(template => 'web/submatrix',
        test     => $test,
        pversion => $pversion,
        reports  => $reports,
    );
}

sub about ($c) {
    return $c->render(template => 'web/about',
        app_name    => $c->app->config->{app_name}    // 'Perl 5 Core Smoke DB',
        app_version => $c->app->config->{app_version} // '2.0',
        perl_version  => $],
        mojo_version  => Mojolicious->VERSION,
        sqlite_version => eval { $c->app->sqlite->db->query('SELECT sqlite_version() AS v')->hash->{v} } // 'unknown',
        db_version    => eval {
            $c->app->sqlite->db->query("SELECT value FROM tsgateway_config WHERE name = 'dbversion'")->hash->{value}
        } // 'unknown',
    );
}

sub full_report ($c) {
    my $rid    = $c->stash('rid');
    my $report = $c->app->reports->full_report_data($rid)
        // return $c->render(status => 404, template => 'web/404');
    return $c->render(template => 'web/full_report', report => $report);
}

sub log_file ($c) {
    my $bytes = $c->app->report_files->read($c->stash('rid'), 'log_file')
        // return $c->render(status => 404, template => 'web/404');
    return $c->render(template => 'web/plain_text',
        title => 'log_file', content => $bytes);
}

sub out_file ($c) {
    my $bytes = $c->app->report_files->read($c->stash('rid'), 'out_file')
        // return $c->render(status => 404, template => 'web/404');
    return $c->render(template => 'web/plain_text',
        title => 'out_file', content => $bytes);
}

sub not_found ($c) {
    return $c->render(status => 404, template => 'web/404');
}

1;
