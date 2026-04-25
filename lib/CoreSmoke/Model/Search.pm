package CoreSmoke::Model::Search;
use v5.42;
use warnings;
use experimental qw(signatures);

# Compile the legacy /api/searchresults filter parameters into a
# parameterised SQL WHERE clause. Names are preserved verbatim so
# existing clients keep working.
#
# Filter inputs (each optional):
#   selected_arch / andnotsel_arch       -> r.architecture
#   selected_osnm / andnotsel_osnm       -> r.osname
#   selected_osvs / andnotsel_osvs       -> r.osversion
#   selected_host / andnotsel_host       -> r.hostname
#   selected_comp / andnotsel_comp       -> c.cc          (joins config)
#   selected_cver / andnotsel_cver       -> c.ccversion   (joins config)
#   selected_perl                        -> "all" | "latest" | "<perl_id>"
#   selected_branch                      -> r.smoke_branch
#   page                                 -> 1-based, default 1
#   reports_per_page                     -> default 25

sub new ($class, %args) {
    my $sqlite = $args{sqlite} // die "sqlite required";
    return bless { sqlite => $sqlite }, $class;
}

my %REPORT_FIELD = (
    arch   => 'r.architecture',
    osnm   => 'r.osname',
    osvs   => 'r.osversion',
    host   => 'r.hostname',
    branch => 'r.smoke_branch',
);
my %CONFIG_FIELD = (
    comp => 'c.cc',
    cver => 'c.ccversion',
);

sub compile ($self, $params) {
    my @where;
    my @bind;

    my $emit = sub ($col, $key) {
        my $v = $params->{"selected_$key"};
        return unless defined $v && length $v && $v ne 'all';
        my $not = $params->{"andnotsel_$key"} ? '<>' : '=';
        push @where, "$col $not ?";
        push @bind, $v;
    };

    $emit->($REPORT_FIELD{$_}, $_) for qw(arch osnm osvs host branch);

    my $needs_config_join = 0;
    for my $key (qw(comp cver)) {
        my $v = $params->{"selected_$key"};
        $needs_config_join = 1 if defined $v && length $v && $v ne 'all';
    }
    if ($needs_config_join) {
        $emit->($CONFIG_FIELD{$_}, $_) for qw(comp cver);
    }

    my $perl = $params->{selected_perl} // 'all';
    if ($perl eq 'latest') {
        push @where, "r.plevel = (SELECT MAX(plevel) FROM report)";
    }
    elsif ($perl ne 'all' && length $perl) {
        push @where, "r.perl_id = ?";
        push @bind, $perl;
    }

    my $sql_from  = "FROM report r"
                  . ($needs_config_join ? " JOIN config c ON c.report_id = r.id" : "");
    my $sql_where = @where ? "WHERE " . join(' AND ', @where) : '';

    return ($sql_from, $sql_where, \@bind);
}

sub run ($self, $params) {
    my ($from, $where, $bind) = $self->compile($params);
    my $rpp    = int($params->{reports_per_page} || 25);
    my $page   = int($params->{page} || 1);
    my $offset = ($page - 1) * $rpp;

    my $db = $self->{sqlite}->db;

    my $count = $db->query(
        "SELECT COUNT(DISTINCT r.id) AS n $from $where",
        @$bind,
    )->hash->{n} // 0;

    my $rows = $db->query(
        "SELECT DISTINCT r.* $from $where "
      . "ORDER BY r.plevel DESC, r.smoke_date DESC LIMIT ? OFFSET ?",
        @$bind, $rpp, $offset,
    )->hashes->to_array;

    return {
        reports          => $rows,
        report_count     => $count,
        page             => $page,
        reports_per_page => $rpp,
    };
}

1;
