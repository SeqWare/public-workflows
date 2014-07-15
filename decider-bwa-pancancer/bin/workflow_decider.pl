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

say 'Removing cached ini and settings samples';
`rm $ARGV{'--working-dir'}/samples/ -rf`;

say 'Getting SeqWare Cluster Information';
my ($cluster_information, $running_samples) 
          = SeqWare::Cluster->cluster_seqware_information( $report_file,
                                                  $ARGV{'--seqware-clusters'}, 
                                                  $ARGV{'--schedule-ignore-failed'});


say 'Getting Sample Information from GNOS';
my $sample_information = GNOS::SampleInformation->get( $ARGV{'--working-dir'},
                                              $ARGV{'--gnos-url'},
                                              $ARGV{'--use-live-cached'},
                                              $ARGV{'--use-cached-analysis'});

say 'Scheduling Samples';
SeqWare::Schedule->schedule_samples( $report_file,
                                     $sample_information,
                                     $cluster_information,
                                     $running_samples,
                                     $ARGV{'--workflow-skip-schedule'},
                                     $ARGV{'--schedule-sample'}, 
                                     $ARGV{'--schedule-center'},
                                     $ARGV{'--schdeule-ignore-lane-count'},
                                     $ARGV{'--seqware-settings'},
                                     $ARGV{'--output-dir'},
                                     $ARGV{'--workflow-output-prefix'},
                                     $ARGV{'--schedule-force-run'},
                                     $ARGV{'--workflow-bwa-threads'},
                                     $ARGV{'--workflow-skip-gtdownload'}, 
                                     $ARGV{'--workflow-skip-gtupload'},
                                     $ARGV{'--workflow-upload-results'}, 
                                     $ARGV{'--workflow-input-prefix'},
                                     $ARGV{'--gnos-url'},
                                     $ARGV{'--schedule-ignore-failed'},
                                     $ARGV{'--working-dir'});



close $report_file;

say 'Finished!!'
