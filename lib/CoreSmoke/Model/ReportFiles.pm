package CoreSmoke::Model::ReportFiles;
use v5.42;
use experimental qw(signatures);

# Stub. Plan 06 fills this in.

sub new ($class, %args) {
    my $root   = $args{root}   // die "root required";
    my $sqlite = $args{sqlite} // die "sqlite required";
    return bless { root => $root, sqlite => $sqlite }, $class;
}

sub path_for ($self, $hash) {
    my $shard = join('/',
        substr($hash, 0, 2),
        substr($hash, 2, 2),
        substr($hash, 4, 2),
        $hash,
    );
    return "$self->{root}/$shard";
}

sub write ($self, $hash, $files) {
    return;   # filled in by plan 06
}

sub read ($self, $rid, $field) {
    return;   # filled in by plan 06
}

1;
