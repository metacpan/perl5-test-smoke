package CoreSmoke::Model::Reports;
use v5.42;
use warnings;
use experimental qw(signatures);

use CoreSmoke::Model::Search;
use CoreSmoke::Model::Matrix;

sub new ($class, %args) {
    my $sqlite       = $args{sqlite}       // die "sqlite required";
    my $report_files = $args{report_files};   # may be undef in some test paths
    return bless {
        sqlite       => $sqlite,
        report_files => $report_files,
        _search      => undef,
        _matrix      => undef,
    }, $class;
}

sub _search ($self) {
    $self->{_search} //= CoreSmoke::Model::Search->new(sqlite => $self->{sqlite});
}

sub _matrix ($self) {
    $self->{_matrix} //= CoreSmoke::Model::Matrix->new(sqlite => $self->{sqlite});
}

sub version ($self) {
    my $row = eval {
        $self->{sqlite}->db->query(
            "SELECT value FROM tsgateway_config WHERE name = 'dbversion'"
        )->hash;
    };
    my $db_version = ($row && $row->{value}) // '4';
    return {
        version        => '2.0',
        schema_version => '4',
        db_version     => $db_version,
    };
}

# /api/latest -- latest report per hostname, ordered by plevel desc.
sub latest ($self, $params = {}) {
    my $rpp  = int($params->{reports_per_page} || 25);
    my $page = int($params->{page} || 1);
    my $offset = ($page - 1) * $rpp;

    my $db = $self->{sqlite}->db;

    my $rows = $db->query(<<~'SQL', $rpp, $offset)->hashes->to_array;
        WITH ranked AS (
            SELECT *,
                   ROW_NUMBER() OVER (
                       PARTITION BY hostname
                       ORDER BY plevel DESC, smoke_date DESC
                   ) AS rn
              FROM report
        )
        SELECT * FROM ranked
         WHERE rn = 1
         ORDER BY plevel DESC, smoke_date DESC
         LIMIT ? OFFSET ?
        SQL

    my $count_row = $db->query(<<~'SQL')->hash;
        SELECT COUNT(*) AS n FROM (
            SELECT 1 FROM report GROUP BY hostname
        )
        SQL

    my $latest_plevel = $db->query("SELECT MAX(plevel) AS p FROM report")->hash->{p};

    return {
        reports          => $rows,
        report_count     => $count_row->{n} // 0,
        latest_plevel    => $latest_plevel  // '',
        rpp              => $rpp,
        page             => $page,
    };
}

sub report_data ($self, $rid) {
    my $db = $self->{sqlite}->db;
    my $report = $db->query("SELECT * FROM report WHERE id = ?", $rid)->hash
        or return;

    my $configs = $db->query(
        "SELECT * FROM config WHERE report_id = ? ORDER BY id", $rid
    )->hashes->to_array;

    for my $cfg (@$configs) {
        my $results = $db->query(
            "SELECT * FROM result WHERE config_id = ? ORDER BY id", $cfg->{id}
        )->hashes->to_array;

        for my $res (@$results) {
            my $failures = $db->query(<<~'SQL', $res->{id})->hashes->to_array;
                SELECT f.test, f.status, f.extra
                  FROM failures_for_env ffe
                  JOIN failure f ON f.id = ffe.failure_id
                 WHERE ffe.result_id = ?
                 ORDER BY f.test
                SQL
            $res->{failures} = $failures;
        }
        $cfg->{results} = $results;
    }
    $report->{configs} = $configs;

    if (defined $report->{sconfig_id}) {
        my $sc = $db->query(
            "SELECT md5, config FROM smoke_config WHERE id = ?", $report->{sconfig_id}
        )->hash;
        $report->{_config} = $sc;
    }

    return $report;
}

sub full_report_data ($self, $rid) {
    my $report = $self->report_data($rid) // return;

    # Aggregate views the legacy UI uses.
    my %compilers;
    my %test_failures;
    my $total_duration = 0;

    for my $cfg (@{ $report->{configs} // [] }) {
        $total_duration += $cfg->{duration} // 0;
        my $cv = join(' ', grep { defined && length } $cfg->{cc}, $cfg->{ccversion});
        $compilers{$cv}++ if length $cv;

        for my $res (@{ $cfg->{results} // [] }) {
            for my $f (@{ $res->{failures} // [] }) {
                $test_failures{ $f->{test} }++;
            }
        }
    }

    $report->{c_compilers}  = [ sort keys %compilers ];
    $report->{test_failures} = [ sort keys %test_failures ];
    $report->{durations}     = $total_duration;

    return $report;
}

sub logfile ($self, $rid) {
    return unless $self->{report_files};
    my $bytes = $self->{report_files}->read($rid, 'log_file');
    return defined $bytes ? { file => $bytes } : undef;
}

sub outfile ($self, $rid) {
    return unless $self->{report_files};
    my $bytes = $self->{report_files}->read($rid, 'out_file');
    return defined $bytes ? { file => $bytes } : undef;
}

sub searchparameters ($self) {
    my $db = $self->{sqlite}->db;
    return {
        sel_arch_os_ver => $db->query(<<~'SQL')->hashes->to_array,
            SELECT DISTINCT architecture, osname, osversion
              FROM report
             ORDER BY architecture, osname, osversion
            SQL
        sel_comp_ver => $db->query(<<~'SQL')->hashes->to_array,
            SELECT DISTINCT cc, ccversion
              FROM config
             WHERE cc IS NOT NULL
             ORDER BY cc, ccversion
            SQL
        branches => [
            map { $_->{smoke_branch} }
            @{ $db->query(<<~'SQL')->hashes->to_array }
                SELECT DISTINCT smoke_branch FROM report ORDER BY smoke_branch
                SQL
        ],
        perl_versions => [
            map { $_->{perl_id} }
            @{ $db->query(<<~'SQL')->hashes->to_array }
                SELECT DISTINCT perl_id FROM report ORDER BY plevel DESC
                SQL
        ],
    };
}

sub searchresults ($self, $params) {
    return $self->_search->run($params);
}

# For the /search UI: given the user's current $filter, return the
# distinct values still possible for each dropdown dimension when all
# OTHER filters are applied. Picking selected_arch=aarch64 narrows the
# perl_version and branch dropdowns to only what exists in aarch64
# rows; the architecture dropdown still shows every architecture so
# the user can change their mind.
#
# Returns:
#   { architectures => [...], perl_versions => [...], branches => [...] }
sub available_filter_values ($self, $filter) {
    my $search = $self->_search;
    my $db     = $self->{sqlite}->db;

    my %dims = (
        architectures => { exclude => [qw(selected_arch   andnotsel_arch)],
                           field   => 'r.architecture',
                           order   => 'r.architecture' },
        perl_versions => { exclude => [qw(selected_perl)],
                           field   => 'r.perl_id',
                           order   => 'r.plevel DESC' },
        branches      => { exclude => [qw(selected_branch andnotsel_branch)],
                           field   => 'r.smoke_branch',
                           order   => 'r.smoke_branch' },
    );

    my %out;
    for my $dim (keys %dims) {
        my %f = %$filter;
        delete @f{ @{ $dims{$dim}{exclude} } };
        my ($from, $where, $bind) = $search->compile(\%f);
        my $sql = "SELECT DISTINCT $dims{$dim}{field} AS v $from $where ORDER BY $dims{$dim}{order}";
        $out{$dim} = [
            grep { defined && length }
            map  { $_->{v} }
            @{ $db->query($sql, @$bind)->hashes->to_array }
        ];
    }

    return \%out;
}

sub matrix ($self) {
    return $self->_matrix->matrix;
}

sub submatrix ($self, $test, $pversion = undef) {
    return $self->_matrix->submatrix($test, $pversion);
}

sub reports_from_id ($self, $rid, $limit = 100) {
    $limit = int($limit || 100);
    return [
        map { $_->{id} }
        @{ $self->{sqlite}->db->query(
            "SELECT id FROM report WHERE id >= ? ORDER BY id LIMIT ?",
            $rid, $limit
        )->hashes->to_array }
    ];
}

sub reports_from_epoch ($self, $epoch) {
    # Convert the epoch into ISO 8601 UTC TEXT for comparison.
    my @t  = gmtime($epoch);
    my $iso = sprintf '%04d-%02d-%02dT%02d:%02d:%02dZ',
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0];

    return [
        map { $_->{id} }
        @{ $self->{sqlite}->db->query(
            "SELECT id FROM report WHERE smoke_date >= ? ORDER BY id",
            $iso
        )->hashes->to_array }
    ];
}

1;
