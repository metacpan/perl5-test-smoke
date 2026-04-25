package CoreSmoke::Model::DB;
use v5.42;
use experimental qw(signatures);
use Mojo::SQLite;
use Digest::MD5 qw(md5_hex);

sub new ($class, %args) {
    my $path = $args{path}                     // die "DB path required";
    my $migs = $args{migrations_sql}           // die "migrations_sql required";
    my $self = bless {
        path           => $path,
        migrations_sql => $migs,
        _sqlite        => undef,
    }, $class;
    return $self;
}

sub sqlite ($self) {
    $self->{_sqlite} //= do {
        my $path = $self->{path};
        my $dir  = $path =~ s{/[^/]+$}{}r;
        require File::Path;
        File::Path::make_path($dir) if length $dir && !-d $dir;
        my $s = Mojo::SQLite->new("sqlite:$path");
        $s->on(connection => sub ($sqlite, $dbh) {
            $dbh->do('PRAGMA foreign_keys = ON');
            $dbh->do('PRAGMA journal_mode = WAL');
        });
        $s->migrations->from_file("$self->{migrations_sql}")->name('coresmoke');
        $s;
    };
}

sub migrate ($self) {
    $self->sqlite->migrations->migrate;
}

sub db ($self) { $self->sqlite->db }

sub pragma_check ($self) {
    return {
        foreign_keys => $self->db->query('PRAGMA foreign_keys')->hash->{foreign_keys},
        journal_mode => $self->db->query('PRAGMA journal_mode')->hash->{journal_mode},
    };
}

sub report_hash ($self, $data) {
    return md5_hex(join "\0",
        map { $data->{$_} // '' }
        qw(git_id smoke_date duration hostname architecture));
}

1;
