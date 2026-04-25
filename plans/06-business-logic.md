# 06 — Business logic (search, matrix, paging, on-disk files)

## Goal

Recreate the data-access logic the legacy `Client::Database` provides as plain SQL in `Model::Reports`, `Model::Search`, `Model::Matrix`, plus add `Model::ReportFiles` for the new on-disk file storage. The trickiest pieces are the AND/NOT search compiler, the failure matrix aggregation, and reading the xz-compressed files transparently.

## Modules

| Module | Responsibility |
|--------|---------------|
| `Model::Reports` | Single-row and small-result-set lookups: `latest`, `full_report_data`, `report_data`, `version`, `reports_from_id`, `reports_from_epoch`, `searchparameters`. Calls `Model::ReportFiles` for `logfile` / `outfile`. |
| `Model::Search` | The filter compiler used by `searchresults`. Translates the `selected_*` / `andnotsel_*` query parameters into a parameterised `WHERE` clause and runs the count + page queries. |
| `Model::Matrix` | `matrix` and `submatrix` aggregations. |
| `Model::ReportFiles` | Read/write the on-disk file tree. Handles sharded path computation and xz compression/decompression. |
| `Model::Plevel` | (already covered in plan 02) |
| `Model::Ingest` | (already covered in plan 05) |

## `Model::ReportFiles`

```perl
package CoreSmoke::Model::ReportFiles;
use v5.42;
use experimental qw(signatures);
use IO::Compress::Xz   qw(xz $XzError);
use IO::Uncompress::UnXz qw(unxz $UnXzError);
use File::Path qw(make_path);

sub new ($class, %args) {
    return bless { root => $args{root}, sqlite => $args{sqlite} }, $class;
}

# data/reports/AB/CD/EF/<full-hash>/
sub path_for ($self, $hash) {
    my $shard = join('/', substr($hash, 0, 2), substr($hash, 2, 2), substr($hash, 4, 2), $hash);
    return "$self->{root}/$shard";
}

sub write ($self, $hash, $files) {
    my $dir = $self->path_for($hash);
    make_path($dir) unless -d $dir;
    for my $field (keys %$files) {
        my $bytes = $files->{$field};
        my $out;
        xz(\$bytes => \$out, Preset => 6) or do {
            warn "xz $field for $hash failed: $XzError";
            next;   # best-effort (decision #33)
        };
        my $path = "$dir/$field.xz";
        open my $fh, '>:raw', $path or do { warn "write $path: $!"; next };
        print $fh $out;
        close $fh;
    }
}

sub read ($self, $rid, $field) {
    my $hash = $self->_hash_for_rid($rid) // return undef;
    my $path = $self->path_for($hash) . "/$field.xz";
    return undef unless -f $path;
    open my $fh, '<:raw', $path or return undef;
    my $compressed = do { local $/; <$fh> };
    my $out;
    unxz(\$compressed => \$out) or return undef;
    return $out;
}

sub _hash_for_rid ($self, $rid) {
    return $self->{sqlite}->db->query(
        'SELECT report_hash FROM report WHERE id = ?', $rid
    )->hash->{report_hash};
}

1;
```

`logfile` and `outfile` DAO methods (called by both REST controllers and the JSONRPC dispatcher) delegate here.

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
SELECT DISTINCT architecture, osname, osversion FROM report ORDER BY architecture, osname, osversion;
SELECT DISTINCT cc, ccversion FROM config ORDER BY cc, ccversion;
SELECT DISTINCT smoke_branch FROM report ORDER BY smoke_branch;
SELECT DISTINCT perl_id FROM report ORDER BY plevel DESC;
```

## `latest`

Latest report per hostname, ordered by plevel desc. Returns:

```
{
  "reports":      [<report_summary>, ...],
  "report_count": 23,
  "latest_plevel":"5.042000zzz000",
  "rpp":          25,
  "page":         1
}
```

(Default `rpp = 25`, decision #26.) SQL using a window function:

```sql
WITH ranked AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY hostname ORDER BY plevel DESC, smoke_date DESC) AS rn
  FROM report
)
SELECT * FROM ranked WHERE rn = 1 ORDER BY plevel DESC LIMIT ? OFFSET ?;
```

## `searchresults` — the filter compiler

Lives in `Model::Search`. Inputs (preserve legacy names):

| Param | Type | Sense |
|-------|------|-------|
| `selected_arch`, `selected_osnm`, `selected_osvs`, `selected_host`, `selected_perl`, `selected_branch` | string | match equals |
| `selected_comp`, `selected_cver` | string | match against `config.cc` / `config.ccversion` |
| `andnotsel_arch`, `andnotsel_osnm`, `andnotsel_osvs`, `andnotsel_host`, `andnotsel_comp`, `andnotsel_cver` | `0`/`1` | flip the corresponding selected_* match into a `<>` NOT match |
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
      "5.41.10": { "cnt": 0, "alt": "" }
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

- `legacy/api/lib/CoreSmokeDB/Client/Database.pm` — every method this file implements maps onto the modules above.
- `legacy/api/lib/CoreSmokeDB/API/Web.pm` — `rpc_failures_matrix`, `rpc_failures_submatrix`, `rpc_get_search_results`.

## Verification

1. `t/60-search.t` — load 5 hand-built fixture reports. Run `searchresults` with each filter combination and assert the right subset is returned.
2. AND/NOT inversion: `selected_arch=x86_64, andnotsel_arch=1` returns only reports where architecture is *not* x86_64.
3. `selected_perl=latest` returns reports whose plevel equals MAX(plevel).
4. `t/61-matrix.t` — load 3 reports across 2 perl versions with overlapping failures; matrix shape and counts match.
5. `t/62-submatrix.t` — given a known failing test, returns exactly the reports that include that failure.
6. `Model::ReportFiles::write` then `Model::ReportFiles::read` round-trips arbitrary bytes through xz; missing files return undef without exception.
