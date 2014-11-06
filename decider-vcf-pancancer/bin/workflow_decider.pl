#!/usr/bin/env perl

use common::sense;
use utf8;

use IPC::System::Simple;
use autodie qw(:all);

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Getopt::Euclid;

use Config::Simple;

use lib '../lib';
use SeqWare::Cluster;
use SeqWare::Schedule;
use GNOS::SampleInformation;

use Decider::Database;
use Decider::Config;

use Data::Dumper;

# add information from config file into %ARGV parameters.
my %ARGV = %{Decider::Config->get(\%ARGV)};

open my $report_file, '>', "$Bin/../".$ARGV{'--report'};

say 'Removing cached ini and settings samples hello';
`rm $Bin/../$ARGV{'--working-dir'}/samples/ -rf`;

my $whitelist = {};
my $blacklist = {};
get_list($ARGV{'--schedule-whitelist-sample'}, 'white', 'sample', $whitelist);
get_list($ARGV{'--schedule-whitelist-donor'},  'white', 'donor',  $whitelist);
get_list($ARGV{'--schedule-blacklist-sample'}, 'black', 'sample', $blacklist);
get_list($ARGV{'--schedule-blacklist-donor'},  'black', 'donor',  $blacklist);

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
				     $ARGV{'--schedule-donor'},
                                     $ARGV{'--schdeule-ignore-lane-count'},
                                     $ARGV{'--seqware-settings'},
                                     $ARGV{'--workflow-output-dir'},
                                     $ARGV{'--workflow-output-prefix'},
                                     $ARGV{'--schedule-force-run'},
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


# Grab contents of white/black list file
sub get_list {
    my $path  = shift or return undef;
    my $color = shift;
    my $type  = shift;
    my $list  = shift;

    my $file = "$Bin/../${color}list/$path";
    die "${color}list does not exist: $file" if (not -e $file);
    
    open my $list_file, '<', $file;
    
    my @list_raw = <$list_file>;
    my @list = grep(s/\s*$//g, @list_raw);
    
    close $list_file;
    
    $list->{$type} = \@list;
}

