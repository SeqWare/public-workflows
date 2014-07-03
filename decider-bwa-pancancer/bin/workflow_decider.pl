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

my $skip_upload = 1;
my $use_gtdownload = 1;
my $use_gtupload = 1;
my $upload_results = 0;
my $ignore_failed = 0;
my $skip_cached = 0;
my $skip_gtdownload = 0;
my $skip_gtupload = 0;
my $input_prefix = "";

open my $report_file, '>', $ARGV{'--report'};

my ($cluster_info, $running_samples) = SeqWare::Cluster->cluster_seqware_information($ARGV{'--json-cluster'}, $report_file);

my $sample_info = GNOS::SampleInformation->get($ARGV{'--working-dir'}, $ARGV{'--gnos_url'}, $ARGV{'--skip-gtdownload'}, $skip_cached, $ARGV{'--test'});

# now look at each sample, see if it's already schedule, launch if not and a cluster is available, and then exit
SeqWare::Schedule->schedule_samples($sample_info, $report_file, $ARGV{'--sample'}, $gnos_url, $input_prefix, $ARGV{'--ignore_lane_count'}, $ARGV{'settings'}, $ARGV{'--output-dir'}, $ARGV{'--output-prefix'}, $ARGV{'--force-run'}, $ARGV{'--threads'});

close $report_file;
