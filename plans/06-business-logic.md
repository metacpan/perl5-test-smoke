# 06 — Business logic (search, matrix, paging)

## Goal

Recreate the data-access logic the legacy `Client::Database` provides, but expressed as plain SQL in `Model::Reports`, `Model::Search`, and `Model::Matrix`. The tricky parts are the multi-field AND/NOT search compiler and the failure matrix aggregation.

## Modules

| Module | Responsibility |
|--------|---------------|
| `Model::Reports` | Single-row and small-result-set lookups: `latest`, `full_report_data`, `report_data`, `logfile`, `outfile`, `version`, `reports_from_id`, `reports_from_epoch`, `searchparameters`. |
| `Model::Search` | The filter compiler used by `searchresults`. Translates the `selected_*` / `andnotsel_*` query parameters into a parameterised `WHERE` clause and runs the count + page queries. |
| `Model::Matrix` | `matrix` and `submatrix` aggregations. |
| `Model::Plevel` | (already covered in plan 02) |

## `searchparameters`

Returns drop-down option sources (legacy keys preserved):

```json
{
  "sel_arch_os_ver": [ {"architecture":"x86_64","osname":"linux","osversion":"6.5"}, ... ],
  "sel_comp_ver":    [ {"cc":"gcc","ccversion":"13.2.0"}, ... ],
  "branches":        ["blead","maint-5.40","maint-5.42"],
  "perl_versions":   ["5.42.0","5.41.10","5.40.0", ...]
}
```

SQL:

```sql
-- sel_arch_os_ver
SELECT DISTINCT architecture, osname, osversion FROM report ORDER BY architecture, osname, osversion;

-- sel_comp_ver
SELECT DISTINCT cc, ccversion FROM config ORDER BY cc, ccversion;

-- branches
SELECT DISTINCT smoke_branch FROM report ORDER BY smoke_branch;

-- perl_versions: distinct perl_id ordered by plevel desc
SELECT DISTINCT perl_id FROM report ORDER BY plevel DESC;
```

## `latest`

Latest report per hostname, ordered by plevel desc. Legacy returns:

```
{
  "reports": [<report_summary>, ...],
  "report_count": 23,
  "latest_plevel": "5.042000zzz000",
  "rpp": 25,
  "page": 1
}
```

SQL using a window function (SQLite supports them since 3.25):

```sql
WITH ranked AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY hostname ORDER BY plevel DESC, smoke_date DESC) AS rn
  FROM report
)
SELECT * FROM ranked WHERE rn = 1 ORDER BY plevel DESC;
```

## `searchresults` — the filter compiler

Lives in `Model::Search`. Inputs (preserve legacy names):

| Param | Type | Sense |
|-------|------|-------|
| `selected_arch`, `selected_osnm`, `selected_osvs`, `selected_host`, `selected_perl`, `selected_branch` | string | match equals |
| `selected_comp`, `selected_cver` | string | match against `config.cc` / `config.ccversion` |
| `andnotsel_arch`, `andnotsel_osnm`, `andnotsel_osvs`, `andnotsel_host`, `andnotsel_comp`, `andnotsel_cver` | `0` or `1` | flip the corresponding selected_* match into a `<>` NOT match |
| `page` | integer | 1-based |
| `reports_per_page` | integer | default 25 |

Build query:

```perl
sub compile ($self, $params) {
    my @where;
    my @bind;

    my %report_field = (
        arch   => 'r.architecture',
        osnm   => 'r.osname',
        osvs   => 'r.osversion',
        host   => 'r.hostname',
        branch => 'r.smoke_branch',
    );
    my %config_field = (
        comp   => 'c.cc',
        cver   => 'c.ccversion',
    );

    my $emit = sub ($col, $key) {
        my $v = $params->{"selected_$key"};
        return unless defined $v && length $v && $v ne 'all';
        my $not = $params->{"andnotsel_$key"} ? '<>' : '=';
        push @where, "$col $not ?";
        push @bind, $v;
    };

    $emit->($report_field{$_}, $_) for qw(arch osnm osvs host branch);
    my $needs_config_join = grep { defined $params->{"selected_$_"} && $params->{"selected_$_"} ne 'all' }
                            qw(comp cver);
    $emit->($config_field{$_}, $_) for qw(comp cver) if $needs_config_join;

    # Perl version: 'all' / 'latest' / explicit
    my $perl = $params->{selected_perl} // 'all';
    if ($perl eq 'latest') {
        push @where, "r.plevel = (SELECT MAX(plevel) FROM report)";
    } elsif ($perl ne 'all' && length $perl) {
        push @where, "r.perl_id = ?";
        push @bind, $perl;
    }

    my $sql_from  = "FROM report r" . ($needs_config_join ? " JOIN config c ON c.report_id = r.id" : "");
    my $sql_where = @where ? "WHERE " . join(' AND ', @where) : '';

    return ($sql_from, $sql_where, \@bind);
}
```

Then count + page:

```perl
sub run ($self, $params) {
    my ($from, $where, $bind) = $self->compile($params);
    my $rpp  = int($params->{reports_per_page} || 25);
    my $page = int($params->{page} || 1);
    my $offset = ($page - 1) * $rpp;

    my $count = $self->db->query("SELECT COUNT(DISTINCT r.id) AS n $from $where", @$bind)->hash->{n};
    my $rows  = $self->db->query(
        "SELECT DISTINCT r.* $from $where ORDER BY r.plevel DESC, r.smoke_date DESC LIMIT ? OFFSET ?",
        @$bind, $rpp, $offset
    )->hashes->to_array;

    return {
        reports          => $rows,
        report_count     => $count,
        page             => $page,
        reports_per_page => $rpp,
    };
}
```

## `matrix`

Cross-tab: rows = test names, columns = last 5 Perl versions (by `plevel desc`). Each cell `{cnt, alt}` where `cnt` is failure count and `alt` is `;`-joined `osname-osversion` distinct list.

```sql
WITH last5 AS (
  SELECT DISTINCT perl_id FROM report ORDER BY plevel DESC LIMIT 5
),
failure_data AS (
  SELECT f.test, r.perl_id,
         COUNT(*) AS cnt,
         GROUP_CONCAT(DISTINCT r.osname || '-' || r.osversion) AS alt
  FROM failure f
  JOIN failures_for_env ffe ON ffe.failure_id = f.id
  JOIN result   rs ON rs.id = ffe.result_id
  JOIN config   c  ON c.id  = rs.config_id
  JOIN report   r  ON r.id  = c.report_id
  WHERE r.perl_id IN (SELECT perl_id FROM last5)
  GROUP BY f.test, r.perl_id
)
SELECT * FROM failure_data ORDER BY cnt DESC, test;
```

Pivot in Perl into the legacy matrix shape:

```json
{
  "perl_versions": ["5.42.0","5.41.10",...],
  "rows": [
    { "test": "lib/foo.t",
      "5.42.0":  { "cnt": 3, "alt": "linux-6.5;darwin-23.0" },
      "5.41.10": { "cnt": 0, "alt": "" },
      ...
    }
  ]
}
```

## `submatrix`

Reports failing one specific test, optionally filtered by `pversion`:

```sql
SELECT r.id, r.perl_id, r.git_id, r.git_describe, r.hostname, r.osname, r.osversion, r.plevel
FROM report r
JOIN config c   ON c.report_id = r.id
JOIN result rs  ON rs.config_id = c.id
JOIN failures_for_env ffe ON ffe.result_id = rs.id
JOIN failure f  ON f.id = ffe.failure_id
WHERE f.test = ?
  AND (? IS NULL OR r.perl_id = ?)
ORDER BY r.plevel DESC, r.smoke_date DESC;
```

## Critical files to read

- `legacy/api/lib/Perl5/CoreSmokeDB/Client/Database.pm` — every method this file implements maps onto the modules above. Trace each to its caller in `Web.pm` to nail down the exact response shape.
- `legacy/api/lib/Perl5/CoreSmokeDB/API/Web.pm` — `rpc_failures_matrix`, `rpc_failures_submatrix`, `rpc_get_search_results`.

## Verification

1. `t/60-search.t` — load 5 hand-built fixture reports varying every filter dimension. Run `searchresults` with each filter combination and assert the right subset is returned.
2. AND/NOT inversion: `selected_arch=x86_64, andnotsel_arch=1` returns only reports where architecture is *not* x86_64.
3. `selected_perl=latest` returns reports whose plevel equals MAX(plevel).
4. `t/61-matrix.t` — load 3 reports across 2 perl versions with overlapping failures; matrix shape and counts match.
5. `t/62-submatrix.t` — given a known failing test, returns exactly the reports that include that failure.
6. `searchparameters` returns the correct distinct sets.
