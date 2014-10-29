#!/usr/bin/perl
#
# File: filter_out_blacklist.pl  by Marc Perry
# 
# 
# 
#
# Last Updated: 2014_09-07, Status: prototype

use strict;
use warnings;
use Data::Dumper;

if (!$ARGV[0]) {
  print STDERR "\nUsage:\n";
  print STDERR "$0 table.txt\n\n";
  exit;
}

my $file = shift;

open my ($FH), '<', $file or die "Couldn't open " . $file . " for reading: $!";
my $input;

{
    local $/ = undef;
    $input = <$FH>;
}

close $FH;

my @lines = split( /[\r\n]/, $input );

open my ($BU), ">", "b_" . $file or die "Couldn't open backup file " . "b_" . $file . " for writing: $!";
print $BU join( "\n", @lines );
close $FH;

open my ($BL), '<', 'blacklist.txt' or die "Couldn't open blacklist.txt for reading: $!";
my @blacklist = <$BL>;
chomp( @blacklist );

open my ($OUT), '>', $file or die "Couldn't open $file for writing: $!";

foreach my $line ( @lines ) {
    my $matched = 0;
    foreach my $bl ( @blacklist ) {
        if ( $line =~ m/$bl/ ) {
            $matched = 1;
            last;
	}
    }
    print $OUT $line, "\n" unless $matched;
} # close foreach loop

exit;

__END__

# Try this from Stackexchange

my @array3 = grep { ! ( $_ ~~ @array2 ) } @array1;

