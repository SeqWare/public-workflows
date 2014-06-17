#!/usr/bin/env perl

# filtering reads in SAM by flags

use strict;
use Getopt::Long;
use Data::Dumper;

my @flags = qw/PAIRED PROPER_PAIR UNMAP MUNMAP REVERSE MREVERSE READ1 READ2 SECONDARY QCFAIL DUP SUPPLEMENTARY/;
my $flags = {};

my $opts = &setup();

# streaming in is the SAM entries
OUTTER: while(<STDIN>){
    if (/^\@/) {
        print;
        next;
    }

    chomp;
    my @F = split /\t/, $_, -1;

    &dec2flag($F[1]);

    my $exclude = @{$opts->{f}} > 0 ? 1 : 0;
    foreach(@{$opts->{f}}){
        $exclude *= $flags->{$_};
    }
    next if $exclude;

    foreach(@{$opts->{r}}){
        next OUTTER unless $flags->{$_} eq "1"; # skip if any of the required flags does not exist
    }

    print "$_\n";
}


sub setup {
    $flags->{$_} = 0 for @flags; # initiate the flags
    
    my %opts;
    my @random_args;
    GetOptions( 'h|help' => \$opts{'h'},
                'r|require=s' => \@{$opts{'r'}},
                'f|filter=s' => \@{$opts{'f'}},
    );
  
    &validate_flag_option(\%opts) || die "Invalid flag used, see above for details!\n";
  
    return \%opts;
}

sub validate_flag_option {
    my $opts = shift;

    for (qw/r f/) {
        for (@{$opts->{$_}}) {
            unless (exists $flags->{$_}) {
                warn "Invalid flag: '$_'\n";
                return 0;
            }
        }
    }

    return 1;
}

sub dec2flag {
    my $str = unpack("B32", pack("N", shift));

    my @bits = split //, $str;

    $flags->{$_} = pop @bits for @flags;

    return $flags;
}

