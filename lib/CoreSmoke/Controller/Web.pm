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
    $page = 1 if $page < 1;
    my $rpp  = int($c->param('reports_per_page') || 25);
    $rpp = 500 if $rpp > 500;
    my $data = $c->app->reports->latest({ page => $page, reports_per_page => $rpp });

    my $is_htmx = _is_htmx($c);

    # Cheap aggregate stats for the hero block (full-page renders only).
    my %stats;
    if (!$is_htmx) {
        my $row = $c->app->sqlite->db->query(q{
            SELECT COUNT(*) AS total_reports,
                   SUM(CASE WHEN smoke_date >= datetime('now','-1 day')
                                 AND summary GLOB 'FAIL*' THEN 1 ELSE 0 END) AS fails_24h,
                   SUM(CASE WHEN smoke_date >= datetime('now','-1 day')
                                 AND summary = 'PASS'     THEN 1 ELSE 0 END) AS pass_24h
            FROM report
        })->hash;
        %stats = map { $_ => ($row->{$_} // 0) } qw(total_reports fails_24h pass_24h);
    }

    my $tmpl    = $is_htmx ? 'web/_reports_rows' : 'web/latest';
    return $c->render(template => $tmpl,
        path             => '/latest',
        reports          => $data->{reports},
        report_count     => $data->{report_count},
        page             => $page,
        reports_per_page => $rpp,
        latest_plevel    => $data->{latest_plevel},
        # The fragment emits an OOB update for #latest-summary only on
        # HTMX requests; on a regular page load the OOB markup would
        # duplicate the inline element.
        oob_summary      => $is_htmx,
        stats            => \%stats,
    );
}

sub search ($c) {
    my %filter;
    for my $key (qw(
        selected_arch selected_osnm selected_osvs selected_host
        selected_comp selected_cver selected_perl selected_branch
        selected_smkv selected_summary
        andnotsel_arch andnotsel_osnm andnotsel_osvs andnotsel_host
        andnotsel_comp andnotsel_cver andnotsel_smkv andnotsel_summary
        page reports_per_page
    )) {
        my $v = $c->param($key);
        $filter{$key} = $v if defined $v;
    }
    my $page    = int($filter{page}             || 1);
    $page = 1 if $page < 1;
    my $rpp     = int($filter{reports_per_page} || 25);
    $rpp = 500 if $rpp > 500;

    # Resolve `selected_perl=latest` once for the whole request via the
    # RPM-style version sort, then feed the same concrete perl_id into
    # both the cascading-dropdown query and the result query. The
    # template still gets the original \%filter so the dropdown renders
    # with `latest` selected.
    my %effective = %filter;
    if (($effective{selected_perl} // '') eq 'latest') {
        $effective{selected_perl} = $c->app->reports->latest_perl_id // 'all';
    }
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

    my $available = $c->app->reports->available_filter_values(\%effective);
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
    my $hot = 0;
    for my $row (@{ $data->{rows} // [] }) {
        for my $v (@{ $data->{perl_versions} // [] }) {
            $hot += $row->{$v}{cnt} // 0;
        }
    }
    return $c->render(template => 'web/matrix', %$data, hot_failures => $hot);
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
