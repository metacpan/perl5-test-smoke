# 07 — Server-rendered web templates

## Goal

Replace the Vue 3 SPA in `legacy/web/` with server-rendered Mojolicious EP templates. Single Perl codebase, no Node toolchain. Recreate every page the SPA had.

## Routes

From `legacy/web/src/router/index.js`:

| Vue path | Mojolicious route | Controller action | Template |
|---------|------------------|-------------------|----------|
| `/`, `/latest` | `GET /` and `GET /latest` | `Web#latest` | `web/latest.html.ep` |
| `/search` | `GET /search` | `Web#search` | `web/search.html.ep` |
| `/matrix` | `GET /matrix` | `Web#matrix` | `web/matrix.html.ep` |
| `/submatrix` | `GET /submatrix` | `Web#submatrix` | `web/submatrix.html.ep` |
| `/about` | `GET /about` | `Web#about` | `web/about.html.ep` |
| `/report/:reportId` | `GET /report/:rid` | `Web#full_report` | `web/full_report.html.ep` |
| `/file/log_file/:reportId` | `GET /file/log_file/:rid` | `Web#log_file` | `web/plain_text.html.ep` |
| `/file/out_file/:reportId` | `GET /file/out_file/:rid` | `Web#out_file` | `web/plain_text.html.ep` |
| `*` (404) | fallback | `Web#not_found` | `web/404.html.ep` |

These web routes are **separate** from `/api/*`. They render HTML that calls the in-process DAO directly (no internal HTTP hop).

## Template layout

```
templates/
├── layouts/
│   └── default.html.ep        # outer chrome: head + nav + footer
├── partials/
│   ├── menu.html.ep            # the nav bar (replaces P5SDBMenu.vue)
│   ├── reports_table.html.ep   # report row table (replaces P5SDBReportsTable.vue)
│   └── search_form.html.ep     # filter form (replaces P5SDBSearchForm.vue)
└── web/
    ├── latest.html.ep
    ├── search.html.ep
    ├── matrix.html.ep
    ├── submatrix.html.ep
    ├── full_report.html.ep
    ├── plain_text.html.ep
    ├── about.html.ep
    └── 404.html.ep
```

`layouts/default.html.ep` includes `<%= include 'partials/menu' %>`, links `coresmokedb.css`, contains `<%= content %>`.

## Static assets

Copy from `legacy/web/src/assets/` into `public/`:

- `coresmokedb.css` (the bulk of the styling — keep as-is)
- `main.css`
- `coresmokedb_logo.gif`
- `smoking_union.gif`
- favicons from `legacy/web/public/`

Mojolicious serves `public/` automatically.

## Forms vs JS

The SPA used Axios + Vuex. We do plain HTML forms with GET submissions:

- `search_form.html.ep` posts via `GET /search?selected_arch=...` — Mojolicious receives the same query params the legacy `/api/searchresults` accepts, so the search controller passes them straight through to `Model::Search`.
- The matrix drill-down is a plain anchor: `<a href="/submatrix?test=<%= url_escape $row->{test} %>&pversion=<%= $perl %>">`.
- The plain-text file viewer is just `<pre><%= $content %></pre>`.

If a few interactions need progressive enhancement (e.g. AND/NOT toggle changing the filter visually before submission), use ~50 lines of vanilla JS in `public/coresmokedb.js`. No bundler.

## Controller pattern

```perl
package Perl5::CoreSmoke::Controller::Web;
use v5.42;
use experimental qw(signatures);
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub latest ($c) {
    my $data = $c->app->reports->latest;
    return $c->render(template => 'web/latest', %$data);
}

sub search ($c) {
    my $params = $c->app->reports->searchparameters;
    my %filter = map { $_ => $c->param($_) } qw(
        selected_arch selected_osnm selected_osvs selected_host
        selected_comp selected_cver selected_perl selected_branch
        andnotsel_arch andnotsel_osnm andnotsel_osvs andnotsel_host
        andnotsel_comp andnotsel_cver
        page reports_per_page
    );
    my $results = $c->app->reports->searchresults(\%filter);
    return $c->render(template => 'web/search',
        params  => $params,
        filter  => \%filter,
        results => $results,
    );
}
# ...
```

## About page

The legacy About page lists framework versions. New version:

```ep
<h2>About</h2>
<dl>
  <dt>App</dt>      <dd>Perl5::CoreSmoke <%= $version %></dd>
  <dt>Perl</dt>     <dd><%= $] %></dd>
  <dt>Mojolicious</dt><dd><%= Mojolicious->VERSION %></dd>
  <dt>SQLite</dt>   <dd><%= $sqlite_version %></dd>
  <dt>DB version</dt><dd><%= $db_version %></dd>
</dl>
```

## Critical files to read

- `legacy/web/src/router/index.js`  (page list)
- `legacy/web/src/components/*.vue` (markup and labels to copy)
- `legacy/web/src/assets/coresmokedb.css` (CSS to copy)

## Verification

1. `t/70-web.t` — Test::Mojo:
   - `GET /` returns 200, contains the latest reports table.
   - `GET /search` renders the empty form.
   - `GET /search?selected_arch=x86_64` filters correctly.
   - `GET /matrix` and `/submatrix?test=foo` render.
   - `GET /report/123` returns 404 if absent, 200 with full report when present.
   - `GET /file/log_file/123` serves the BLOB inside `<pre>`.
   - Nav links resolve to existing routes.
2. Manual smoke after ingesting the fixture: each page loads in a browser.
3. Visual diff vs the legacy SPA is *not* a goal — pages should be functional and laid out using the same CSS, but tiny differences are fine.
