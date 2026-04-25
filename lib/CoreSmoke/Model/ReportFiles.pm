package CoreSmoke::Model::ReportFiles;
use v5.42;
use warnings;
use experimental qw(signatures);

use IO::Compress::Xz     qw(xz   $XzError);
use IO::Uncompress::UnXz qw(unxz $UnXzError);
use File::Path qw(make_path);
use File::Temp ();

# The five fields we externalize from the legacy report.bytea columns.
my @FIELDS = qw(log_file out_file manifest_msgs compiler_msgs nonfatal_msgs);
my %IS_FIELD = map { $_ => 1 } @FIELDS;

sub new ($class, %args) {
    my $root   = $args{root}   // die "root required";
    my $sqlite = $args{sqlite} // die "sqlite required";
    return bless { root => $root, sqlite => $sqlite }, $class;
}

# data/reports/AB/CD/EF/<full-hash>/
sub path_for ($self, $hash) {
    my $shard = join('/',
        substr($hash, 0, 2),
        substr($hash, 2, 2),
        substr($hash, 4, 2),
        $hash,
    );
    return "$self->{root}/$shard";
}

# Write the (possibly partial) set of fields to disk under the report's hash dir.
# $files is { field_name => bytes_or_string }. Best-effort: we log and continue
# on individual file failure rather than aborting the whole insert (decision #33).
sub write ($self, $hash, $files) {
    return unless ref $files eq 'HASH';
    my $dir = $self->path_for($hash);
    make_path($dir) unless -d $dir;

    for my $field (keys %$files) {
        next unless $IS_FIELD{$field};
        my $bytes = $files->{$field};
        next unless defined $bytes && length $bytes;

        my $compressed;
        unless (xz(\$bytes => \$compressed, Preset => 6)) {
            warn "[report_files] xz $field for $hash failed: $XzError";
            next;
        }

        my $path = "$dir/$field.xz";
        my $tmp  = File::Temp->new(
            DIR    => $dir,
            SUFFIX => '.tmp',
            UNLINK => 0,
        );
        binmode $tmp;
        print {$tmp} $compressed;
        if (!close $tmp) {
            warn "[report_files] write ${\$tmp->filename}: $!";
            unlink $tmp->filename;
            next;
        }
        if (!rename($tmp->filename, $path)) {
            warn "[report_files] rename ${\$tmp->filename} -> $path: $!";
            unlink $tmp->filename;
        }
    }
    return;
}

# Read one field by report id. Returns the decompressed bytes, or undef on miss.
sub read ($self, $rid, $field) {
    return unless $IS_FIELD{$field};
    my $hash = $self->_hash_for_rid($rid) // return;
    return $self->read_by_hash($hash, $field);
}

sub read_by_hash ($self, $hash, $field) {
    return unless $IS_FIELD{$field};
    my $path = $self->path_for($hash) . "/$field.xz";
    return unless -f $path;

    open my $fh, '<:raw', $path or return;
    my $compressed = do { local $/; <$fh> };
    close $fh;

    my $out;
    unless (unxz(\$compressed => \$out)) {
        warn "[report_files] unxz $path: $UnXzError";
        return;
    }
    return $out;
}

sub _hash_for_rid ($self, $rid) {
    my $row = $self->{sqlite}->db->query(
        'SELECT report_hash FROM report WHERE id = ?', $rid
    )->hash;
    return $row ? $row->{report_hash} : undef;
}

sub has_file ($self, $hash, $field) {
    return unless $IS_FIELD{$field};
    return -f ($self->path_for($hash) . "/$field.xz") ? 1 : 0;
}

sub fields { return @FIELDS }

1;
