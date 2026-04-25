# Design system

This is the long-form companion to the terse rule in `CLAUDE.md`
("Design system: use it, don't reinvent it"). When in doubt, **read
the visual reference** at `docs/design-system/metacpan-design-system.html`
in a browser — it shows every component live in both themes.

## Why this exists

The CoreSmoke UI is built on the MetaCPAN design system: a token-first
CSS layer (colors, spacing, typography, motion) wrapped around ~36
pure-CSS components. We extracted just the components we use into
`public/coresmoke.css` and built a thin layer of Mojolicious helpers
and partials so templates compose from the same vocabulary instead of
inventing markup per page.

The goal is consistency: a new page should feel like the existing
ones without anyone having to think about colors, spacing, or
typography. If the system can't express something, that's a signal
the system needs extending — not a license to bypass it.

## Tokens cheat-sheet

All defined in `:root` (light) and overridden in `[data-theme="dark"]`.

### Colors

| Token | When to use |
|-------|-------------|
| `--bg-canvas` | The page background. |
| `--bg-surface` | Cards, panels, inputs, table backgrounds. |
| `--bg-subtle` | Subtle stripe (e.g. `<thead>`, hover row). |
| `--bg-muted` | Slightly stronger neutral (e.g. badge background). |
| `--fg-primary` | Body text. |
| `--fg-secondary` | Field labels, footer, less prominent text. |
| `--fg-tertiary` | Help text, breadcrumb separator, captions. |
| `--fg-disabled` | Disabled or hint text. |
| `--accent` / `--accent-hover` / `--accent-press` | Primary brand action color (CPAN red). |
| `--accent-soft` | Tinted background for active states. |
| `--link` / `--link-hover` | Inline links (teal, separates from accent). |
| `--success-*` / `--warning-*` / `--danger-*` / `--info-*` | Semantic colors. Use the `*-50` for backgrounds, `*-500` for fills, `*-700` for foreground on light bg. |
| `--border-subtle` / `--border-default` / `--border-strong` | Border weights — pick the lightest that reads. |

### Spacing — `--space-0` through `--space-12`

`0, 4px, 8px, 12px, 16px, 24px, 32px, 40px, 48px, 64px, 80px, 96px, 128px`.

Stick to this scale. Never write a literal pixel value for margin,
padding, or gap.

### Typography

- `--font-display` — Fraunces. Headings only (`h1`–`h4`,
  `.page-header-title`, `.card-title`).
- `--font-sans` — Inter. Body text, labels, buttons.
- `--font-mono` — JetBrains Mono. Code, version strings, IDs,
  badges, the matrix axis, breadcrumbs.

Sizes: `--text-2xs` (11) ... `--text-4xl` (48). Match the existing
usage rather than inventing new size combinations.

### Other

- `--radius-sm` (4) for badges/inputs, `--radius-md` (6) for
  buttons/cards, `--radius-lg` (10) for major panels, `--radius-full`
  for pills/dots.
- `--shadow-sm` for resting cards, `--shadow-md` on hover,
  `--shadow-lg` for overlays/toasts. `--shadow-focus` is auto-applied
  by `:focus-visible` rules.
- `--dur-fast` (120ms) for hovers, `--dur-base` (200ms) for state
  changes, `--dur-slower` (500ms) for prominent transitions. Always
  pair with `--ease-out` (or `--ease-in-out`).

## Component map

### Helpers (`lib/CoreSmoke/App.pm`)

| Helper | Signature | Use for |
|--------|-----------|---------|
| `badge`       | `badge($text, $variant?)` | Inline badge. Variants: `success`, `warning`, `danger`, `info`, `accent`. |
| `status_pill` | `status_pill($summary)` | Smoke summary -> badge with the right variant. |
| `nav_link`    | `nav_link($label, $href)` | Topbar nav link with auto-active state. |
| `btn_link`    | `btn_link($label, $href, $variant?, $size?)` | Anchor styled as a button. Variants: `primary`, `secondary` (default), `ghost`, `danger`, `link`. Sizes: `sm`, `lg`. |
| `asset_url`   | `asset_url('/coresmoke.css')` | Returns `/coresmoke.css?v=<mtime>` for cache busting. Stat is closure-cached. |

### Partials (`templates/components/`)

| Partial | Required params | Optional | Renders |
|---------|-----------------|----------|---------|
| `hero`               | `title` | `eyebrow`, `lede`, `stats` | Big landing-page hero. `title` may contain `<em>` for italic accent. `stats` is `[{ label, value, variant?, trend? }]`. |
| `stat`               | `label`, `value` | `variant`, `trend` | Standalone stat (label + big Fraunces value). Variants: `success`, `danger`, `accent`. |
| `page_header`        | `crumbs`, `title` | `subtitle`, `actions` | Top-of-page breadcrumb + H1 + action slot. |
| `breadcrumb`         | `crumbs` | — | Breadcrumb nav. |
| `card`               | `body` | `title`, `meta` | Surface card. |
| `alert`              | `variant`, `body` | `title` | Banner alert. |
| `data_table`         | `headers`, `body` | `tbody_id`, `extra_class` | Bordered table with sticky `<thead>`, zebra rows, hover. `headers` entries can be a string OR `{ label, sort => '<key>' }` to enable client-side column sort. |
| `pagination_summary` | `shown`, `total` | `noun`, `id`, `oob`, `extra` | "Showing N of M reports" line. Carries `data-count` for toast. |
| `code_block`         | `body` | `lang` | Dark-themed `<pre>` with optional language label. |
| `empty_state`        | `title` | `desc`, `icon`, `actions` | Centered "nothing to show" block. |
| `form_field`         | `label`, `name`, `type` | `value`, `options`, `extra`, `help`, `placeholder` | Labeled input or select. |
| `tabs`               | `group`, `active`, `tabs`, `panels` | — | Aria-tab list + panels. |
| `spinner`            | — | `label` | Indeterminate spinner. |
| `skeleton_rows`      | `cols` | `count` | Shimmer rows for HTMX loading state. |
| `status_chips`       | `param`, `base`, `options` | `current`, `carry` | Quick-filter chip cluster. |

For partials accepting a content slot (`body`, `actions`, etc.), pass
a Mojolicious `begin ... end` block:

```ep
%= include 'components/card', title => 'Stack', body => begin
  <p>Body markup here, supports <strong>raw HTML</strong>.</p>
% end
```

The partial detects code refs and calls them; raw strings would be
HTML-escaped, which is rarely what you want for component bodies.

## Adding a new component

1. **Find it in the design system reference**
   (`docs/design-system/metacpan-design-system.html`). Most things you
   need are already there — check before inventing.
2. **Copy only what you need into `public/coresmoke.css`**, keeping
   the comment block delimiters. Use only existing tokens — never
   introduce a new hex.
3. If the component is reused in more than one place, **add a partial**
   in `templates/components/` (or a helper in `App.pm` if it's a tiny
   inline bit). Partials should accept content via `begin/end` blocks
   for raw markup.
4. **Update this file's component map** so the next person finds it
   before re-inventing it.
5. If you discovered a token gap or an architectural pattern worth
   warning about, add a one-liner to `CLAUDE.md`'s "Design system"
   section.

## Dark mode discipline

The bootstrap script in `templates/layouts/default.html.ep`'s `<head>`
runs synchronously and sets `data-theme` on `<html>` from
`localStorage.theme` (falling back to `prefers-color-scheme`). The
topbar toggle calls `window.toggleTheme()` from `app.js`.

Rules:

- Use `--bg-*` and `--fg-*` aliases, never the raw `--ink-*` /
  `#FFFFFF` / `rgba(...)`. The aliases are remapped in the dark theme.
- Test every change in BOTH themes by clicking the topbar toggle.
  Common breakage: hard-coded `color: black` on text inside a coloured
  alert; `background: white` on a panel; SVG icons with hard-coded
  stroke colors.
- Borders: `--border-subtle` for subdivisions inside a surface,
  `--border-default` for the outer edge of a panel.

## HTMX integration recipes

(See also `CLAUDE.md` -> "HTMX recipes that work here" for the rules
that pre-date the design system.)

- **Skeleton rows during load-more**: the `_reports_rows` partial
  renders the trigger row as
  `<tr class="skeleton-row hx-load-more" hx-trigger="revealed" ...>`.
  The shimmer animation provides feedback; on swap, it's replaced by
  real rows + a fresh trigger row. Don't add a separate spinner.
- **Filter-change toast**: `app.js` listens for `htmx:afterSwap` on
  `#search-region`. If the request was triggered by `#search-form`,
  it reads `data-count` from the swapped `.pagination-summary` and
  toasts "N reports match". The hook fires once per filter change.
- **Empty state on zero results**: the `_search_region` partial
  conditionally renders `empty_state` instead of an empty
  `data_table`. This works for both the full page and the HTMX swap
  because the partial is the same in both.
- **OOB updates**: `pagination_summary` accepts `oob => 1` and emits
  `hx-swap-oob="true"`. Pair with the same `id` on both the inline
  and OOB renders so HTMX can target it.

## Cache busting (asset_url)

Every static asset URL in `templates/layouts/default.html.ep` (and any
template that links to a CSS/JS/image we ship) goes through the
`asset_url` helper:

```ep
<link rel="stylesheet" href="<%= asset_url '/coresmoke.css' %>">
<script src="<%= asset_url '/app.js' %>" defer></script>
<img class="brand-logo" src="<%= asset_url '/logo.png' %>" alt="">
```

The helper appends `?v=<mtime>` (epoch seconds of the file on disk).
The mtime is stat'd once per worker per asset (closure-cached), so
there's no per-request stat overhead. After editing CSS or JS, run
`make reload` to restart workers — the new mtime is picked up
automatically and browser caches invalidate.

The query-string strategy was chosen over content-hashed filenames
because it requires zero extra build/startup machinery and works
identically in dev and production.

## Tables — power features

The `data_table` partial composes several behaviours wired in
`coresmoke.css` and `app.js`:

- **Zebra striping**: alternating rows tinted with `--bg-subtle`.
- **Sticky header**: `<thead>` sticks during table scroll.
- **Hover rows**: `--bg-subtle` on hover; `--accent-soft` if the row
  has a `data-href` (click target).
- **Clickable rows**: add `data-href="/report/<id>"` on a `<tr>` and
  the JS in `app.js` navigates on click. Inner anchors/buttons keep
  their own behaviour.
- **Status emphasis**: rows get `row-accent-<variant>` (3px left
  border) AND the status `<td>` gets `status-cell-<variant>` (faint
  semantic background) so the status column reads from across the
  table.
- **Client-side column sort**: pass `headers => [{ label, sort => 'key' }, ...]`
  to declare sortable columns. Each `<td>` carries
  `data-sort-key="key"` and optionally `data-sort-value="..."` for
  non-text comparison (e.g. ISO date strings). Sort runs in the
  browser, scoped to the visible page; no controller changes needed.
- **Density toggle**: the topbar density button toggles
  `body.density-compact`; rows shrink to `--space-2` padding +
  `--text-xs` font size. Persisted in `localStorage.density`.

## Anti-patterns

- **Inline `style="color: red"` for a status indicator** -> use
  `status_pill` or a `.badge-danger`.
- **Building a one-off table with raw `<table>` + custom CSS** ->
  use the `data_table` partial.
- **Adding a new hex color "just for this page"** -> if a semantic
  variant doesn't fit, the system is wrong. Discuss before extending.
- **Renaming a class to fit a personal preference** -> stick with
  the design-system names so cross-page diffs stay readable.
- **Catching a missing component by inlining the markup** -> add it
  to `templates/components/` instead, even if first used in only one
  place. Future you will thank you.
