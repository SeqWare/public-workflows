use strict;

my $header_file = $ARGV[0];
my $bed_file = $ARGV[1];

my $missing_mate_names = &get_missing_mate_names($bed_file);

print &header($header_file);

while(<STDIN>){
    chomp;

    my $rg = $1 if (/.+(RG:Z:.+?)(\s.*|\Z)/);

    my @F = split /\t/;

    my $uniq_read_name = join ("~", ($F[0], $rg, $F[2], $F[3]));

    print "$_\n" if $missing_mate_names->{$uniq_read_name};
}

# subroutines

sub header {
    my $header_file = shift;

    open (H, "< $header_file") || die "Could not open the header file!";

    my $header = "";
    while(<H>){
        s/\\t/\t/g;
        $header .= $_ unless (/^\@PG/);
    }

    close(H);

    return $header;
}

sub get_missing_mate_names {
    my $bed_file = shift;

    open(BED, "< $bed_file") || die "Could not open the bed file!";

    my $missing_mate_names = {};
    while(<BED>) {
        chomp;

        my @F = split /\t/;

        $missing_mate_names->{$F[3]."~".$F[0]."~".$F[2]}++;
    }
    close(BED);

    return $missing_mate_names;
}
