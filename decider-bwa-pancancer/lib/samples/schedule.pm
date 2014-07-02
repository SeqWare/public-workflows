package Samples::Schedule

use common::sense;

use IPC::System::Simple;
use autodie qw(:all);

#use Capture::Tiny ':all';

#use File::Slurp;

#use XML::DOM;
#use Data::Dumper;
#use JSON;
#use Getopt::Long;
#use XML::LibXML;
#use Cwd;

sub schedule_workflow {
    my ($d, $seqware_settings_file, $report_file) = @_;

    my $rand = substr(rand(), 2);

    my $settings = new Config::Simple($seqware_settings_file);
 
    my $cluster = (keys %{$cluster_info})[0];
    my  $cluster_found = (defined $cluster)? 1: 0;
    my $url = $cluster_info->{$cluster}{webservice};
    my $username = $cluster_info->{$cluster}{username};
    my $password = $cluster_info->{$cluster}{password};
    my $workflow_accession = $cluster_info->{$cluster}{workflow_accession};
    $workflow_accession //= 0;
    my $workflow_version = $cluster_info->{$cluster}{workflow_version};
    $workflow_version //= '2.5.0';
    my $host = $cluster_info->{$cluster}{host};
    $host //= 'unknown';

    delete $cluster_info->{$cluster};

    $settings->update('SW_REST_URL', $url);
    $settings->update('SW_REST_USER', $username);
    $settings->update('SW_REST_PASS',$password);

    # can only assign one workflow here per cluster
    $cluster_found = 1;

    system("mkdir -p $working_dir/$rand");

    $settings->write("$working_dir/$rand/settings");

    my $template_ini = read_file( "template/ini/workflow-$workflow_version.json" ) ; 
    my %workflow_ini = JSON->new->allow_nonref->decode( $template_ini );

    $workflow_ini{input_bam_paths} = join ',', sort keys %{$d->{local_bams}} ;
    $workflow_ini{gnos_input_file_urls} = $d->{gnos_input_file_urls};
    $workflow_ini{gnos_input_metadata_urls} = $d->{analysis_url};
    $workflow_ini{gnos_output_file_url} = $gnos_url;
    $workflow_ini{numOfThreads} = $threads;
    $workflow_ini{use_gtdownload} = ($skip_gtdownload)? 'false': 'true';
    $workflow_ini{use_gtupload} =  ($skip_gtupload)? 'false': 'true';
    $workflow_ini{skip_upload} = ($upload_results)? 'false': 'true';
    $workflow_ini{output_prefix} = $output_prefix;
    $workflow_ini{output_dir} = $output_dir;

    my $settings = new Config::Simple("$working_dir/$rand/workflow.ini");
    foreach my $parameter (keys %workflow_ini) {
        $settings->param($parameter, $workflow_ini{$parameter});
    }
    $settings->save();

    submit_workflow($working_dir, $rand, $workflow_accession, $host, $test, $cluster_found, $report_file, $url);
}

sub submit_workflow {
    my ($working_dir, $rand, $workflow_accession, $host, $test, $cluster_found, $report_file, $url) = @_;

    my $dir = getcwd();

    my $launch_command = "SEQWARE_SETTINGS=$working_dir/$rand/settings /usr/local/bin/seqware workflow schedule --accession $workflow_accession --host $host --ini $working_dir/$rand/workflow.ini";

    if (not $test and $cluster_found) {
       
        say $report_file "\tLAUNCHING WORKFLOW: $working_dir/$rand/workflow.ini";
        say $report_file "\t\tCLUSTER HOST: $host ACCESSION: $workflow_accession URL: $url";
        say $report_file "\t\tLAUNCH CMD: $launch_command";

        open my $temp_script, '>', 'temp_script.sh';
        # FIXME: this is all extremely brittle when executed via cronjobs
        print $temp_script "#!/usr/bin/env bash

source ~/.bashrc

cd $dir
export SEQWARE_SETTINGS=$working_dir/$rand/settings
export PATH=\$PATH:/usr/local/bin
env
seqware workflow schedule --accession $workflow_accession --host $host --ini $working_dir/$rand/workflow.ini

";
        close $temp_script;

        my $temp_script_command = "bash -l $dir/temp_script.sh > submission.out 2> submission.err";

        no autodie qw(system);
        say $report_file "\t\tSOMETHING WENT WRONG WITH SCHEDULING THE WORKFLOW"
             unless (system($temp_script_command) == 0);
    }
    elsif ( not $test and not $cluster_found) {
        say $report_file "\tNOT LAUNCHING WORKFLOW, NO CLUSTER AVAILABLE: $working_dir/$rand/workflow.ini";
        say $report_file "\t\tLAUNCH CMD WOULD HAVE BEEN: $launch_command";
    } 
    else {
        say $report_file "\tNOT LAUNCHING WORKFLOW BECAUSE --test SPECIFIED: $working_dir/$rand/workflow.ini";
        say $report_file "\t\tLAUNCH CMD WOULD HAVE BEEN: $launch_command";
    }
    say $report_file;
}

sub schedule_samples {
    my ($sample_info, $report_file, $specific_sample) = @_;
  
    say $report_file "SAMPLE SCHEDULING INFORMATION\n";

    foreach my $participant (keys %{$sample_info}) {
        schedule_participant($report_file,
                             $sample_info, 
                             $participant, 
                             $specific_sample);
    }
}

sub schedule_patricipant {
    my ($report_file, $sample_info, $participant, $specific_sample) = @_;

    say $report_file "DONOR/PARTICIPANT: $participant\n";

    foreach my $sample (keys %{$sample_info->{$participant}}) {        
        if (not defined $specific_sample || $specific_sample eq $sample) {
            my $alignments = $sample_info->{$participant}{$sample}{$sample};
            schedule_sample($sample, $sample_info, $report_file, $alignments, $gnos_url);
        }
    }
}

sub schedule_sample {
    my($sample, $sample_info, $report_file, $alignments, $gnos_url) = @_;

    say $report_file "\tSAMPLE OVERVIEW";
    say $report_file "\tSPECIMEN/SAMPLE: $sample";

    my $sample = {gnos_url => $gnos_url};
    my $aligns = {};
    foreach my $alignment (keys %{$alignments}) {
        say $report_file "\t\tALIGNMENT: $alignment";
        $aligns->{$alignment} = 1;
        my $aliquotes = $alignments->{$alignment};
        foreach my $aliquot (keys %{$aliquotes}) {
            say $report_file "\t\t\tANALYZED SAMPLE/ALIQUOT: $aliquot";
            my $libraries = $aliquotes->{$aliquot};
            foreach my $library (keys %{$libraries}) {
                say $report_file "\t\t\t\tLIBRARY: $library";
                # read lane counts
                my $total_lanes = $libraries->{$library}{total_lanes};
                foreach my $lane (keys %{$total_lanes}) {
                    $total_lanes = $lane if ($lane > $total_lanes);
                }
                $sample->{total_lanes_hash}{$total_lanes} = 1;
                $sample->{total_lanes} = $total_lanes;
                my $files = $library->{files};
                foreach my $file (keys %{$files}) {
                    my $local_path = $file->{localpath};
                    $sample->{files}{$file} = $local_path;
                    my $local_file_path = $input_prefix.$local_path;
                    $sample->{local_bams}{$local_file_path} = 1;
                    $sample->{bam_count} ++ if ($alignment eq "unaligned");
                 }
                 # analysis
                 my $analyses = $library->{analysis_id};
                 foreach my $analysis (sort keys %{$analyses}) {
                     $sample->{analysis_url}{"$gnos_url/cghub/metadata/analysisFull/$analysis"} = 1;
                     $sample->{download_url}{"$gnos_url/cghub/data/analysis/download/$analysis"} = 1;
                 }
                 $sample->{gnos_input_file_urls} = join ',', sort keys %{$sample->{downloadURL}};
                 say $report_file "\t\t\t\t\tBAMS: ", join ',', keys %{$files};
                 say $report_file "\t\t\t\t\tANALYSIS_IDS: ", join ',', keys %{$library->{analysis_id}}. "\n";
            }
        }
    }

    say $report_file "\tSAMPLE WORKLFOW ACTION OVERVIEW";
    say $report_file "\t\tLANES SPECIFIED FOR SAMPLE: $sample->{total_lanes}";
    say $report_file "\t\tBAMS FOUND: $sample->{bams_count}";
   

    schedule_workflow($sample, $seqware_settings_file)
       if should_be_scheduled($aligns, $force_run, $report_file, $sample, $running_samples);
}

sub should_be_scheduled {
    my ($aligns, $force_run, $report_file, $sample, $running_samples) = @_;

    if ((unaligned($aligns, $report_file) or scheduled($report_file, $sample, $running_samples, $sample))
                                                         and not $force_run) { 
        say $report_file "\t\tCONCLUSION: WILL NOT SCHEDULE THIS SAMPLE FOR ALIGNMENT!"; 
        return 0;
    }

    say $report_file "\t\tCONCLUSION: SCHEDULING WORKFLOW FOR THIS SAMPLE!\n";

    return 1;
}

sub unaligned {
    my ($aligns, $report_file) = @_;

    my $unaligned = $aligns->{unaligned};
    if  (not scalar keys %{$aligns} == 1 && not defined $unaligned ) {
        say $report_file "\t\tCONTAINS ALIGNMENT"; 
        return 1; 
    }
    
    say $report_file "\t\tONLY UNALIGNED";
    return 0;
}

sub scheduled {
    my ($report_file, $sample, $running_samples ) = @_; 

    my $analysis_url_str = join ',', sort keys %{$sample->{analysis_url}};
    $sample->{analysis_url} = $analysis_url_str;

    if ( not defined($running_samples->{$analysis_url_str}) || $force_run) {
        say $report_file "\t\tNOT PREVIOUSLY SCHEDULED OR RUN FORCED!";
    } 
    elsif ($running_samples->{$analysis_url_str} eq "failed" && $ignore_failed) {
        say $report_file "\t\tPREVIOUSLY FAILED BUT RUN FORCED VIA IGNORE FAILED OPTION!";
    } 
    else {
        say $report_file "\t\tIS PREVIOUSLY SCHEDULED, RUNNING, OR FAILED!";
        say $report_file "\t\t\tSTATUS: ".$running_samples->{$analysis_url_str};
        return 1;
    }

    if ($sample->{total_lanes} == $sample->{bams_count} || $ignore_lane_count || $force_run) {
        say $report_file "\t\tLANE COUNT MATCHES OR IGNORED OR RUN FORCED: ignore_lane_count: $ignore_lane_count total lanes: $sample->{total_lanes} bam count: $sample->{bams_count}\n";
    } 
    else {
        say $report_file "\t\tLANE COUNT MISMATCH!";
        return 1;
    }

    return 0;
}

1;
