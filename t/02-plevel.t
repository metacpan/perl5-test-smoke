use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";

use CoreSmoke::Model::Plevel;

my $corpus = "$FindBin::Bin/data/plevel-corpus.tsv";
open my $fh, '<', $corpus or die "open $corpus: $!";
while (my $line = <$fh>) {
    chomp $line;
    next if $line =~ /^\s*(?:#|$)/;
    my ($describe, $expected) = split /\t/, $line, 2;
    next unless defined $expected;
    is(
        CoreSmoke::Model::Plevel::from_git_describe($describe),
        $expected,
        "plevel($describe) = $expected",
    );
}
close $fh;

done_testing;
