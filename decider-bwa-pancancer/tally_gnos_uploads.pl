#!/usr/bin/perl
#
# File tally_gnos_uploads.pl by Marc Perry
# 
# The script slurps in an ascii text file and counts the number of times
# certain values are seen in one of the columns.  It then prints out those
# counts in a very precise order
# 
# Last Updated: 2014-06-26, Status: in development

use strict;
use warnings;
use Data::Dumper;

my @projects = qw( OV-AU PACA-AU PAEN-AU PACA-CA PRAD-CA GACA-CN LICA-FR EOPC-DE MALY-DE PBCA-DE ORCA-IN LINC-JP LIRI-JP BTCA-SG BRCA-KR LAML-KR CLLE-ES BOCA-UK BRCA-EU BRCA-UK CMDI-UK ESAD-UK PRAD-UK BLCA-US BRCA-US CESC-US COAD-US DLBC-US GBM-US HNSC-US KICH-US KIRC-US KIRP-US LAML-US LGG-US LIHC-US LUAD-US LUSC-US OV-US PRAD-US READ-US SARC-US SKCM-US STAD-US THCA-US UCEC-US );

my %counts_of_proj = ();
die "You must specify the name of the table on the command line\n" unless $ARGV[0];


# we want to count and report the number of unique specimens, so 
# if a specimen has been aligned we only want to count that once.
# (i.e., we don't want to count the unaligned row for the specimens because
# that will inflate the number of specimens)
while ( <> ) {
    chomp;
    my @fields = split(/\t/, $_);
    # $fields[0] = the ICGC DCC Project code name
    # $fields[2] = the specimen ID
    # if we have seen this specimen before, then
    # update the hash as requrired
    if ( $counts_of_proj{$fields[0]}{$fields[2]}{paired} ) {
       # I am going to assume that the paired bit does not change
       # so it is just the aligned I want to check
       if ( $fields[5] ne 'unaligned' ) { 
           $counts_of_proj{$fields[0]}{$fields[2]}{aligned} = $fields[5];
       }
    # Otherwise, create a hash for it
    }
    else {
        $counts_of_proj{$fields[0]}{$fields[2]} = { 'paired' => $fields[10],
                                                    'aligned' => $fields[5],
                                                };
    }
} # close while loop

# print
print "Project\tNumber of Specimens Uploaded\tPair Uploaded\tAligned Specimens\tAligned Pairs\n";
foreach my $project ( @projects ) {
    my $total_specimens = 0;
    my $total_paired = 0;
    my $total_aligned = 0;
    my $total_both = 0;
    if ( $counts_of_proj{$project} ) {
        # so here we are just getting a count of the number of specimens that 
        # we've seen
        $total_specimens = scalar( keys %{$counts_of_proj{$project}} );
        foreach my $specimen ( keys %{$counts_of_proj{$project}} ) {
            my $is_paired = 0;
            my $is_aligned = 0;
            if ( $counts_of_proj{$project}{$specimen}{paired} eq 'YES' ) {
                $is_paired = 1;
                $total_paired++;
	    }
            if ( $counts_of_proj{$project}{$specimen}{aligned} ne 'unaligned' ) {
                $is_aligned = 1;
                $total_aligned++;
            }
            if ( $is_paired && $is_aligned ) {
                $total_both++;
	    }
	}
        print "$project\t$total_specimens\t$total_paired\t$total_aligned\t$total_both\n";
    }
    else {
        print "$project\t0\t0\t0\t0\n";
    }
} # close printing foreach loop

exit;

__END__

