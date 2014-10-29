#!/usr/bin/env perl

use common::sense;
use utf8;

use IPC::System::Simple;
use autodie qw(:all);

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Getopt::Euclid;

use Config::Simple;

use SeqWare::Cluster;
use SeqWare::Schedule;
use GNOS::SampleInformation;

use Decider::Database;
use Decider::Config;

use Data::Dumper;

# add information from config file into %ARGV parameters.
my %ARGV = %{Decider::Config->get(\%ARGV)};

open my $report_file, '>', "$Bin/../".$ARGV{'--report'};

say 'Removing cached ini and settings samples';
`rm $Bin/../$ARGV{'--working-dir'}/samples/ -rf`;

my ($whitelist, $blacklist);
$whitelist = get_whitelist($ARGV{'--schedule-whitelist'})
                                       if ($ARGV{'--schedule-whitelist'});
$blacklist = get_blacklist($ARGV{'--schedule-blacklist'})
                                       if ($ARGV{'--schedule-blacklist'});
say 'Getting SeqWare Cluster Information';
my ($cluster_information, $running_sample_ids, $failed_samples, $completed_samples)
          = SeqWare::Cluster->cluster_seqware_information( $report_file,
                                                  $ARGV{'--seqware-clusters'}, 
                                                  $ARGV{'--schedule-ignore-failed'},
                                                  $ARGV{'--workflow-version'});


#my $failed_db = Decider::Database->failed_connect();


say 'Reading in GNOS Sample Information';

my $sample_information = GNOS::SampleInformation->get( $ARGV{'--working-dir'},
                                              $ARGV{'--gnos-url'},
                                              $ARGV{'--use-live-cached'},
                                              $ARGV{'--use-cached-analysis'},
                                              $ARGV{'--lwp-download-timeout'});

say 'Scheduling Samples';
SeqWare::Schedule->schedule_samples( $report_file,
                                     $sample_information,
                                     $cluster_information,
                                     $running_sample_ids,
                                     $ARGV{'--workflow-skip-scheduling'},
                                     $ARGV{'--schedule-sample'}, 
                                     $ARGV{'--schedule-center'},
                                     $ARGV{'--schdeule-ignore-lane-count'},
                                     $ARGV{'--seqware-settings'},
                                     $ARGV{'--workflow-output-dir'},
                                     $ARGV{'--workflow-output-prefix'},
                                     $ARGV{'--schedule-force-run'},
                                     $ARGV{'--workflow-bwa-threads'},
                                     $ARGV{'--workflow-skip-gtdownload'}, 
                                     $ARGV{'--workflow-skip-gtupload'},
                                     $ARGV{'--workflow-upload-results'}, 
                                     $ARGV{'--workflow-input-prefix'},
                                     $ARGV{'--gnos-url'},
                                     $ARGV{'--schedule-ignore-failed'},
                                     $ARGV{'--working-dir'},
                                     $ARGV{'--workflow-version'},
                                     $whitelist,
                                     $blacklist
                                      );

close $report_file;

say 'Finished!!';


sub get_whitelist {
   my ($whitelist_path) = @_;

   my $file = "$Bin/../whitelist/$whitelist_path";
   die "Whitelist does not exist: $file" if (not -e $file);

   open my $whitelist, '<', $file;

   my @whitelist_raw = <$whitelist>;
   my @whitelist = grep(s/\s*$//g, @whitelist_raw);

   close $whitelist;

   return \@whitelist;
}

sub get_blacklist {
   my ($blacklist_path) = @_;

   my $file = "$Bin/../blacklist/$blacklist_path";
   die "Blacklist does not exist: $file" if (not -e $file);

   open my $blacklist, '<', $file;

   my @blacklist_raw = <$blacklist>;
   my @blacklist = grep(s/\s*$//g, @blacklist_raw);
   
   close $blacklist;    

   return \@blacklist;
}
