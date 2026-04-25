package CoreSmoke::Model::Plevel;
use v5.42;
use warnings;
use experimental qw(signatures);

# Faithful port of public.git_describe_as_plevel() from the legacy Postgres
# schema. Output must be byte-identical to the PG function so plevel-keyed
# URLs and existing client expectations keep working after migration.

sub from_git_describe ($describe) {
    my $clean = $describe // '';
    $clean =~ s/^v//;
    $clean =~ s/-g.+$//;
    my @parts = split /[.\-]/, $clean;
    push @parts, '0' if @parts == 3;

    my $plevel = ($parts[0] // '') . '.'
               . _lpad($parts[1] // '', 3, '0')
               . _lpad($parts[2] // '', 3, '0');

    if (defined $parts[3] && $parts[3] =~ /RC/) {
        $plevel .= $parts[3];
    } else {
        $plevel .= 'zzz';
    }

    $plevel .= _lpad($parts[-1] // '', 3, '0');
    return $plevel;
}

# PG lpad(str, len, fill): pads from the left, truncates from the right
# if the string is already longer than `len`.
sub _lpad ($str, $len, $fill) {
    return substr($str, 0, $len) if length($str) > $len;
    return $fill x ($len - length($str)) . $str;
}

1;
