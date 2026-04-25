package CoreSmoke::Model::Reports;
use v5.42;
use experimental qw(signatures);

# Stub. Plans 03 and 06 fill this in.

sub new ($class, %args) {
    my $sqlite = $args{sqlite} // die "sqlite required";
    return bless { sqlite => $sqlite }, $class;
}

sub version ($self) {
    my $db_version = eval {
        $self->{sqlite}->db->query(
            "SELECT value FROM tsgateway_config WHERE name = 'dbversion'"
        )->hash->{value};
    } // '4';
    return {
        version        => '2.0',
        schema_version => '4',
        db_version     => $db_version,
    };
}

sub latest             ($self, $params = {}) { return { reports => [], report_count => 0, latest_plevel => '', rpp => 25, page => 1 } }
sub full_report_data   ($self, $rid)         { return }
sub report_data        ($self, $rid)         { return }
sub matrix             ($self)               { return { perl_versions => [], rows => [] } }
sub submatrix          ($self, $test, $pv = undef) { return [] }
sub searchparameters   ($self)               { return { sel_arch_os_ver => [], sel_comp_ver => [], branches => [], perl_versions => [] } }
sub searchresults      ($self, $params)      { return { reports => [], report_count => 0, page => 1, reports_per_page => 25 } }
sub reports_from_id    ($self, $rid, $limit) { return [] }
sub reports_from_epoch ($self, $epoch)       { return [] }

1;
