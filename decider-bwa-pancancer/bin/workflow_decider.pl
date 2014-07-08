#!/usr/bin/env perl

use common::sense;

use IPC::System::Simple;
use autodie qw(:all);

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Getopt::Euclid;

use SeqWare::Cluster;
use SeqWare::Schedule;
use GNOS::SampleInformation;

open my $report_file, '>', $ARGV{'--report'};

say "Removing cached ini and settings samples if cached";

`rm $ARGV{'--working-dir'}/samples/ -rf`;

say 'Getting SeqWare Cluster Information';
my ($cluster_information, $running_samples) 
          = SeqWare::Cluster->cluster_seqware_information( $report_file,
                                                           $ARGV{'--cluster-json'}, 
                                                           $ARGV{'--ignore-failed'});


say 'Getting Sample Information from GNOS';
my $sample_information = GNOS::SampleInformation->get( $ARGV{'--working-dir'},
                                                       $ARGV{'--gnos-url'},
                                                       $ARGV{'--skip-meta-download'},
                                                       $ARGV{'--skip-cached'});

say 'Scheduling Samples';
SeqWare::Schedule->schedule_samples( $report_file,
                                     $sample_information,
                                     $cluster_information,
                                     $running_samples,
                                     $ARGV{'--test'},
                                     $ARGV{'--sample'}, 
                                     $ARGV{'--ignore_lane_count'},
                                     $ARGV{'--settings'},
                                     $ARGV{'--output-dir'},
                                     $ARGV{'--output-prefix'},
                                     $ARGV{'--force-run'},
                                     $ARGV{'--threads'},
                                     $ARGV{'--skip-gtdownload'}, 
                                     $ARGV{'--skip-gtupload'},
                                     $ARGV{'--upload-results'}, 
                                     $ARGV{'--input-prefix'},
                                     $ARGV{'--gnos-url'},
                                     $ARGV{'--ignore-failed'},
                                     $ARGV{'--working-dir'});

close $report_file;

say 'Finished!!'
