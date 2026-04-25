package CoreSmoke::Model::Ingest;
use v5.42;
use experimental qw(signatures);

# Stub. Plan 05 fills this in.

sub new ($class, %args) {
    my $sqlite = $args{sqlite}       // die "sqlite required";
    my $rf     = $args{report_files} // die "report_files required";
    return bless { sqlite => $sqlite, report_files => $rf }, $class;
}

sub post_report ($self, $data) {
    return { error => 'Not implemented yet.' };
}

1;
