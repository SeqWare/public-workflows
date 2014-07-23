#!/usr/bin/perl
#
# File tally_gnos_paired_uploads.pl by Marc Perry
# Derived from my previous scrip tally_gnos_uploads.pl
# This version counts the number of pairs
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
    # $fields[0] = the ICGC DCC Project code name
    # $fields[1] = the Donor ID
    # $fields[2] = the specimen ID
    my @fields = split(/\t/, $_);
    $counts_of_proj{$fields[0]}{$fields[1]}{$fields[2]}++;
} # close while loop

# print
print "Project\tNumber of Donors Uploaded\tNumber with 2 Specimens\tTotal number of Specimens\n";
foreach my $project ( @projects ) {
    my $total_donors = 0;
    my $total_specimens = 0;
    my $total_paired = 0;
    if ( $counts_of_proj{$project} ) {
        # so here we are just getting a count of the number of specimens that 
        # we've seen
        my @donors = keys %{$counts_of_proj{$project}};
        $total_donors = scalar( @donors );
        foreach my $donor (@donors) {
            my $specimens = scalar ( keys %{$counts_of_proj{$project}{$donor}} );
            $total_specimens += $specimens;
            if ($specimens > 1 ) {
                $total_paired++;
            }
	} # close foreach loop
    print "$project\t$total_donors\t$total_paired\t$total_specimens\n";
    }
    else {
        print "$project\t0\t0\t0\n";
    }
} # close printing foreach loop

exit;

__END__

