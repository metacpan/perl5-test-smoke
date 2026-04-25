# 07 — Server-rendered web templates

## Goal

Replace the Vue 3 SPA in `legacy/web/` with server-rendered Mojolicious EP templates. **Restyle from scratch** (decision #18) — do not copy `legacy/web/src/assets/coresmokedb.css` verbatim. Use **HTMX** (decision #17) for filter forms, matrix drill-down, and **infinite scroll** on `/latest` and `/search` (decision #38).

## Routes

| Mojolicious route | Controller action | Template |
|------------------|-------------------|----------|
| `GET /` and `GET /latest` | `Web#latest` | `web/latest.html.ep` |
| `GET /search` | `Web#search` | `web/search.html.ep` |
| `GET /matrix` | `Web#matrix` | `web/matrix.html.ep` |
| `GET /submatrix` | `Web#submatrix` | `web/submatrix.html.ep` |
| `GET /about` | `Web#about` | `web/about.html.ep` |
| `GET /report/:rid` | `Web#full_report` | `web/full_report.html.ep` |
| `GET /file/log_file/:rid` | `Web#log_file` | `web/plain_text.html.ep` |
| `GET /file/out_file/:rid` | `Web#out_file` | `web/plain_text.html.ep` |
| fallback | `Web#not_found` | `web/404.html.ep` |

These web routes are **separate** from `/api/*`. They render HTML that calls the in-process DAO directly (no internal HTTP hop). `log_file` and `out_file` use `Model::ReportFiles::read` to pull and decompress the xz file from disk.

## HTMX-specific routes (partial fragments)

The same controllers also serve **HTML fragments** when HTMX requests them. Detect via `HX-Request` header (Mojolicious: `$c->req->headers->header('HX-Request')`).

```perl
sub latest ($c) {
    my $page = $c->param('page') || 1;
    my $data = $c->app->reports->latest({ page => $page });
    my $tmpl = $c->req->headers->header('HX-Request')
        ? 'web/_reports_rows'    # fragment: just <tr> rows + the next-page trigger
        : 'web/latest';          # full page
    return $c->render(template => $tmpl, %$data);
}
```

The infinite-scroll trigger at the bottom of `_reports_rows.html.ep`:

```ep
% if ($report_count > $page * $reports_per_page) {
<tr hx-get="/latest?page=<%= $page + 1 %>" hx-trigger="revealed" hx-swap="afterend">
  <td colspan="6"><em>Loading more...</em></td>
</tr>
% }
```

Same pattern for `/search`.

## Template layout

```
templates/
├── layouts/
│   └── default.html.ep          # outer chrome: head + nav + footer
├── partials/
│   ├── menu.html.ep             # top nav
│   └── search_form.html.ep      # filter form (uses hx-get on change)
└── web/
    ├── latest.html.ep
    ├── search.html.ep
    ├── matrix.html.ep
    ├── submatrix.html.ep
    ├── full_report.html.ep
    ├── plain_text.html.ep
    ├── about.html.ep
    ├── 404.html.ep
    ├── _reports_rows.html.ep    # HTMX fragment: report rows + next-page trigger
    └── _matrix_cell.html.ep     # HTMX fragment for cell drill-down
```

`layouts/default.html.ep` includes the menu partial, links `/coresmoke.css` and `/htmx.min.js`, and contains `<%= content %>`.

## Static assets

`public/`:

- `htmx.min.js` — HTMX 1.x or 2.x (whichever is current at implementation time). Vendored.
- `coresmoke.css` — new stylesheet, light theme (decision #39). Decide framework (Pico/Sakura) vs. hand-craft during execution.
- favicons.

Mojolicious serves `public/` automatically.

## Forms vs JS

The filter form on `/search` uses `hx-get="/search"` with `hx-trigger="change delay:200ms"` on each `<select>` so changing a filter immediately re-runs the search and replaces the results region. No page reload.

Matrix drill-down stays as a plain anchor: `<a href="/submatrix?test=<%= url_escape $row->{test} %>&pversion=<%= $perl %>">`.

`plain_text.html.ep` is just `<pre><%= $content %></pre>` — content already decompressed by `Model::ReportFiles`.

## Controller pattern

```perl
package CoreSmoke::Controller::Web;
use v5.42;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub latest ($c) {
    my $page = int($c->param('page') || 1);
    my $data = $c->app->reports->latest({ page => $page });
    my $tmpl = $c->req->headers->header('HX-Request') ? 'web/_reports_rows' : 'web/latest';
    return $c->render(template => $tmpl, %$data);
}

sub search ($c) {
    my %filter = map { $_ => $c->param($_) } qw(
        selected_arch selected_osnm selected_osvs selected_host
        selected_comp selected_cver selected_perl selected_branch
        andnotsel_arch andnotsel_osnm andnotsel_osvs andnotsel_host
        andnotsel_comp andnotsel_cver
        page reports_per_page
    );
    my $params  = $c->app->reports->searchparameters;
    my $results = $c->app->reports->searchresults(\%filter);
    my $tmpl = $c->req->headers->header('HX-Request') ? 'web/_reports_rows' : 'web/search';
    return $c->render(template => $tmpl,
        params  => $params,
        filter  => \%filter,
        results => $results,
    );
}

sub log_file ($c) {
    my $bytes = $c->app->report_files->read($c->stash('rid'), 'log_file')
        // return $c->render(status => 404, template => 'web/404');
    return $c->render(template => 'web/plain_text', content => $bytes);
}
```

## About page

```ep
<h2>About</h2>
<dl>
  <dt>App</dt>        <dd><%= config('app_name') %> v<%= config('app_version') %></dd>
  <dt>Perl</dt>       <dd><%= $] %></dd>
  <dt>Mojolicious</dt><dd><%= Mojolicious->VERSION %></dd>
  <dt>SQLite</dt>     <dd><%= $sqlite_version %></dd>
  <dt>DB version</dt> <dd><%= $db_version %></dd>
</dl>
```

`config('app_name')` returns `"Perl 5 Core Smoke DB"` from the Mojo config (decision #2).

## Critical files to read

- `legacy/web/src/router/index.js`            (page list)
- `legacy/web/src/components/*.vue`           (markup and labels for reference; not blindly copied)
- HTMX docs: https://htmx.org/docs/

## Verification

1. `t/70-web.t` — Test::Mojo:
   - `GET /` returns 200, contains the latest reports table.
   - `GET /search` renders the empty form.
   - `GET /search?selected_arch=x86_64` filters correctly.
   - `GET /matrix` and `/submatrix?test=foo` render.
   - `GET /report/123` returns 404 if absent, 200 with full report when present.
   - `GET /file/log_file/123` decompresses the xz file from disk and serves it inside `<pre>`.
   - Nav links resolve to existing routes.
2. HTMX request returns the fragment template, not the layout: `GET /latest?page=2` with header `HX-Request: true` returns just the `<tr>` rows + next-page trigger.
3. Manual smoke after ingesting the fixture: each page loads in a browser and infinite scroll works.
4. Visual diff vs the legacy SPA is *not* a goal — pages should be functional with a clean modern look.
