package SeqWare::Schedule;

use common::sense;

use IPC::System::Simple;
use autodie qw(:all);

use FindBin qw($Bin);

use Config::Simple;
use Capture::Tiny ':all';
use Cwd;
use Carp::Always;

use Data::Dumper;

sub schedule_samples {
    my ($class, $report_file,
                $sample_information, 
                $cluster_information, 
                $running_samples, 
                $skip_scheduling,
                $specific_sample,
	        $specific_donor,
                $specific_center,
                $ignore_lane_count,
                $seqware_settings_file,
                $output_dir,
                $output_prefix,
                $force_run,
                $threads,
                $skip_gtdownload,
                $skip_gtupload,
                $upload_results,
                $input_prefix, 
                $gnos_url,
                $ignore_failed, 
                $working_dir,
                $run_workflow_version,
                $whitelist,
                $blacklist) = @_;

    say $report_file "SAMPLE SCHEDULING INFORMATION\n";

    my $i = 0;
    foreach my $center_name (keys %{$sample_information}) {
        next if (defined $specific_center && $specific_center ne $center_name);
        say $report_file "SCHEDULING: $center_name";

        foreach my $donor_id (keys %{$sample_information->{$center_name}}) {

	    next if defined $specific_donor and $specific_donor ne $donor_id;

	    my @blacklist = @{$blacklist->{donor}} if $blacklist and $blacklist->{donor};
	    next if defined $blacklist and grep {/^$donor_id$/} @blacklist;

	    my @whitelist = @{$whitelist->{donor}} if $whitelist and $whitelist->{donor};
	    if (not defined $whitelist or grep {/^$donor_id$/} @whitelist) {
	    
		my $donor_information = $sample_information->{$center_name}{$donor_id};
		schedule_donor($report_file,
			       $donor_id, 
			       $donor_information,
			       $cluster_information, 
			       $running_samples, 
			       $skip_scheduling,
			       $specific_sample,
			       $ignore_lane_count,
			       $seqware_settings_file,
			       $output_dir,
			       $output_prefix,
			       $force_run,
			       $threads,
			       $skip_gtdownload,
			       $skip_gtupload,
			       $upload_results,
			       $input_prefix, 
			       $gnos_url,
			       $ignore_failed, 
			       $working_dir, 
			       $center_name, 
			       $run_workflow_version,
			       $whitelist,
			       $blacklist);
	    }
	}
    }
}

sub schedule_workflow {
    my ( $sample, 
         $seqware_settings_file, 
         $report_file,
         $cluster_information,
         $working_dir,
         $threads,
         $gnos_url,
         $skip_gtdownload,
         $skip_gtupload,
         $skip_scheduling,
         $upload_results,
         $output_prefix,
         $output_dir,
         $force_run,
         $running_sample_id,
         $sample_id,
         $center_name,
         $run_workflow_version ) = @_;


   
    my $cluster = (keys %{$cluster_information})[0];
    my $cluster_found = (defined($cluster) and $cluster ne '' )? 1: 0;

    my $url = $cluster_information->{$cluster}{webservice};
    my $username = $cluster_information->{$cluster}{username};
    my $password = $cluster_information->{$cluster}{password};

    my $workflow_accession = $cluster_information->{$cluster}{workflow_accession};
    my $workflow_version = $cluster_information->{$cluster}{workflow_version};
    my $workflow_accession = $cluster_information->{$cluster}{workflow_accession};
    my $workflow_version = $cluster_information->{$cluster}{workflow_version};
    my $host = $cluster_information->{$cluster}{host};

    if ($cluster_found or $skip_scheduling) {
        system("mkdir -p $Bin/../$working_dir/samples/$center_name/$sample_id");

        create_settings_file($seqware_settings_file, $url, $username, $password, $working_dir, $center_name, $sample_id);

        create_workflow_ini($run_workflow_version, $sample, $gnos_url, $threads, $skip_gtdownload, $skip_gtupload, $upload_results, $output_prefix, $output_dir, $working_dir, $center_name, $sample_id);
    }

    submit_workflow($working_dir, $workflow_accession, $host, $skip_scheduling, $cluster_found, $report_file, $url, $center_name, $sample_id);

    delete $cluster_information->{$cluster} if ($cluster_found);
}

sub create_settings_file {
    my ($seqware_settings_file, $url, $username, $password, $working_dir, $center_name, $sample_id) = @_;

    my $settings = new Config::Simple("$Bin/../conf/ini/$seqware_settings_file");

    $url //= '<SEQWARE URL>';
    $username //= '<SEQWARE USER NAME>';
    $password //= '<SEQWARE PASSWORD>';

    $settings->param('SW_REST_URL', $url);
    $settings->param('SW_REST_USER', $username);
    $settings->param('SW_REST_PASS',$password);

    $settings->write("$Bin/../$working_dir/samples/$center_name/$sample_id/settings");
}

sub create_workflow_ini {
    my ($workflow_version, $sample, $gnos_url, $threads, $skip_gtdownload, $skip_gtupload, $upload_results, $output_prefix, $output_dir, $working_dir, $center_name, $sample_id) = @_;

    my $ini_path = "$Bin/../conf/ini/workflow-$workflow_version.ini";
    die "ini template does not exist: $ini_path" unless (-e $ini_path);
    my $workflow_ini = new Config::Simple($ini_path); 

    my $local_bams_string = $sample->{local_bams_string};
    my $gnos_input_file_urls = $sample->{gnos_input_file_urls};
    my $analysis_url_string = $sample->{analysis_url_string};
    
    $workflow_ini->param('input_bam_paths', $local_bams_string) if ($local_bams_string);
    $workflow_ini->param('gnos_input_file_urls', $gnos_input_file_urls) 
                                                             if ($gnos_input_file_urls);
    $workflow_ini->param('gnos_input_metadata_urls', $analysis_url_string)

                                                             if ($analysis_url_string);
    $workflow_ini->param('gnos_output_file_url', $gnos_url);
    $workflow_ini->param('numOfThreads', $threads);
    $workflow_ini->param('use_gtdownload', (defined $skip_gtdownload)? 'false': 'true');
    $workflow_ini->param('use_gtupload',  (defined $skip_gtupload)? 'false': 'true');
    $workflow_ini->param('skip_upload', (defined $upload_results)? 'false': 'true');
    $workflow_ini->param('output_prefix', $output_prefix);
    $workflow_ini->param('output_dir', $output_dir);
    $workflow_ini->param('sample_id', $sample_id);    
  
    $workflow_ini->write("$Bin/../$working_dir/samples/$center_name/$sample_id/workflow.ini");
}


sub submit_workflow {
    my ($working_dir, $workflow_accession, $host, $skip_scheduling, $cluster_found, $report_file, $url, $center_name, $sample_id) = @_;

    my $dir = getcwd();

    my $launch_command = "SEQWARE_SETTINGS=$Bin/../$working_dir/samples/$center_name/$sample_id/settings /usr/local/bin/seqware workflow schedule --accession $workflow_accession --host $host --ini $Bin/../$working_dir/samples/$center_name/$sample_id/workflow.ini";

    if ($skip_scheduling) {
        say $report_file "\tNOT LAUNCHING WORKFLOW BECAUSE --schedule-skip-workflow SPECIFIED: $Bin/../$working_dir/samples/$center_name/$sample_id/workflow.ini";
        say $report_file "\t\tLAUNCH CMD WOULD HAVE BEEN: $launch_command\n";
        return;
    } 
    elsif ($cluster_found) {
        say $report_file "\tLAUNCHING WORKFLOW: $Bin/../$working_dir/samples/$center_name/$sample_id/workflow.ini";
        say $report_file "\t\tCLUSTER HOST: $host ACCESSION: $workflow_accession URL: $url";
        say $report_file "\t\tLAUNCH CMD: $launch_command";

        my $submission_path = 'log/submission';
        `mkdir -p $submission_path`;
        my $out_fh = IO::File->new("$Bin/../$submission_path/$sample_id.o", "w+");
        my $err_fh = IO::File->new("$Bin/../$submission_path/$sample_id.e", "w+");
 
        my ($std_out, $std_err) = capture {
             no autodie qw(system);
             system( "cd $dir;
                      export SEQWARE_SETTINGS=$Bin/../$working_dir/samples/$center_name/$sample_id/settings;
                      export PATH=\$PATH:/usr/local/bin;
                      env;
                      seqware workflow schedule --accession $workflow_accession --host $host --ini $Bin/../$working_dir/samples/$center_name/$sample_id/workflow.ini") 
        };

        print $out_fh $std_out if($std_out);
        print $err_fh $std_err if($std_err);

        say $report_file "\t\tSOMETHING WENT WRONG WITH SCHEDULING THE WORKFLOW: Check error log =>  $Bin/../$submission_path/$sample_id.e and output log => $Bin/../$submission_path/$sample_id.o" if($std_err);
    }
    else {
        say $report_file "\tNOT LAUNCHING WORKFLOW, NO CLUSTER AVAILABLE: $Bin/../$working_dir/samples/$center_name/$sample_id/workflow.ini";
        say $report_file "\t\tLAUNCH CMD WOULD HAVE BEEN: $launch_command";
    } 
    say $report_file '';
}

sub schedule_donor {
    my ( $report_file,
         $donor_id,
         $donor_information,
         $cluster_information, 
         $running_samples, 
         $skip_scheduling,
         $specific_sample,
         $ignore_lane_count,
         $seqware_settings_file,
         $output_dir,
         $output_prefix,
         $force_run,
         $threads,
         $skip_gtdownload,
         $skip_gtupload,
         $upload_results,
         $input_prefix, 
         $gnos_url,
         $ignore_failed,
         $working_dir,
         $center_name,
         $run_workflow_version,
         $whitelist,
         $blacklist ) = @_;

    say $report_file "DONOR/PARTICIPANT: $donor_id\n";
    my @sample_ids = keys %{$donor_information};
    foreach my $sample_id (@sample_ids) {        
	next if defined $specific_sample and $specific_sample ne $sample_id;

	my @blacklist = @{$blacklist->{sample}} if $blacklist and $blacklist->{sample};
	next if defined $blacklist and grep {/^$sample_id$/} @blacklist;

	my @whitelist = @{$whitelist->{sample}} if $whitelist and $whitelist->{sample};
        if (not defined $whitelist or grep {/^$sample_id$/} @whitelist) {
            schedule_sample( $sample_id,
                         $donor_information,
                         $report_file,
                         $gnos_url,
                         $input_prefix,
                         $force_run,
                         $running_samples,
                         $ignore_failed,
                         $ignore_lane_count,
                         $seqware_settings_file,
                         $cluster_information,
                         $working_dir,
                         $threads,
                         $skip_gtdownload,
                         $skip_gtupload,
                         $skip_scheduling,
                         $upload_results,
                         $output_prefix,
                         $output_dir,
                         $center_name,
                         $run_workflow_version);
        }
    }
}

sub schedule_sample {
    my ( $sample_id,
         $donor_information, 
         $report_file,
         $gnos_url,
         $input_prefix,
         $force_run,
         $running_samples, 
         $ignore_failed,
         $ignore_lane_count, 
         $seqware_settings_file,
         $cluster_information,
         $working_dir,
         $threads,
         $skip_gtdownload,
         $skip_gtupload,
         $skip_scheduling,
         $upload_results,
         $output_prefix,
         $output_dir,
         $center_name,
         $run_workflow_version) = @_;

    say $report_file "\tSAMPLE OVERVIEW\n\tSPECIMEN/SAMPLE: $sample_id";

    my $alignments = $donor_information->{$sample_id};
    my $sample = { gnos_url => $gnos_url,
                   bam_count => 0};
    my $aligns = {};

    foreach my $alignment_id (keys %{$alignments}) {
        say $report_file "\t\tALIGNMENT: $alignment_id";
 
        my $aliquotes = $alignments->{$alignment_id};
        foreach my $aliquot_id (keys %{$aliquotes}) {
            say $report_file "\t\t\tANALYZED SAMPLE/ALIQUOT: $aliquot_id";

            my $libraries = $aliquotes->{$aliquot_id};
            foreach my $library_id (keys %{$libraries}) {
                say $report_file "\t\t\t\tLIBRARY: $library_id";
                my $library = $libraries->{$library_id};
                my $current_workflow_version = $library->{workflow_version};
                my @current_workflow_versions = keys $current_workflow_version;
                $current_workflow_version = $current_workflow_versions[0];

                my @current_workflow_version = split /\./, $current_workflow_version;
                my @run_workflow_versions = split /\./, $run_workflow_version;


                #should add to list of aligns if unaliged or the workflow has already been run with a workflow where the first two version numbers are greater than or equal to the desired workflow version. 
                if ( ($alignment_id eq 'unaligned') 
                   or (
                        (defined $current_workflow_version)
                    and ( 
                          ($current_workflow_versions[0] > $run_workflow_versions[0]) 
                        or (
                          ($current_workflow_versions[0] == $run_workflow_versions[0]) 
                           and ($current_workflow_versions[1] >= $run_workflow_versions[1])
                           )
                        )
                      )
                    ) {
                         $aligns->{$alignment_id} = 1;
                }

                my $files = $library->{files};
                my @local_bams;
                foreach my $file (keys %{$files}) {
                    my $local_path = $files->{$file}{local_path};
                       push @local_bams, $local_path if ($local_path =~ /bam$/);
                }
                my @analysis_ids = keys %{$library->{analysis_ids}};
                my $analysis_ids = join ',', @analysis_ids;

                say $report_file "\t\t\t\t\tBAMS: ".join ',', @local_bams;
                say $report_file "\t\t\t\t\tANALYSIS IDS: $analysis_ids\n";

                if ( $alignment_id eq 'unaligned' ) {

                    my $lanes = $library->{total_lanes};
                    my $total_lanes = 0;
                    foreach my $lane (keys %{$lanes}) {
                        $total_lanes = $lane if ($lane > $total_lanes);
                    }
                    $sample->{total_lanes} = $total_lanes;
    
                    foreach my $file (keys %{$files}) {
                        my $local_path = $files->{$file}{local_path};
                        if ($local_path =~ /bam$/) {
                            $sample->{file}{$file} = $local_path;
                            my $local_file_path = $input_prefix.$local_path;
                            $sample->{local_bams}{$local_file_path} = 1;
                            $sample->{bam_count} ++;
                        }
                    }
    
                    my @local_bams = keys %{$sample->{local_bams}};
     
                    $sample->{local_bams_string} = join ',', sort @local_bams;
    
                    foreach my $analysis_id (sort @analysis_ids) {
                        $sample->{analysis_url}{"$gnos_url/cghub/metadata/analysisFull/$analysis_id"} = 1;
                        $sample->{download_url}{"$gnos_url/cghub/data/analysis/download/$analysis_id"} = 1;
                    }

                    my @download_urls = keys %{$sample->{download_url}};
                    $sample->{gnos_input_file_urls} = join ',', sort @download_urls;
       
                    my @analysis_urls = keys %{$sample->{analysis_url}};
                    $sample->{analysis_url_string} = join ',', @analysis_urls;   
    
                }

            }
        }
    }

    say $report_file "\tSAMPLE WORKLFOW ACTION OVERVIEW";
    say $report_file "\t\tLANES SPECIFIED FOR SAMPLE: $sample->{total_lanes}";
    say $report_file "\t\tUNALIGNED BAMS FOUND: $sample->{bam_count}";
    $sample->{sample_id} = $sample_id;

    schedule_workflow( $sample, 
                       $seqware_settings_file, 
                       $report_file,
                       $cluster_information,
                       $working_dir,
                       $threads,
                       $gnos_url,
                       $skip_gtdownload,
                       $skip_gtupload,
                       $skip_scheduling,
                       $upload_results,
                       $output_prefix,
                       $output_dir,
                       $force_run,
                       $running_samples,
                       $sample_id,
                       $center_name,
                       $run_workflow_version )
       if should_be_scheduled( $aligns, 
                               $force_run, 
                               $report_file, 
                               $sample, 
                               $running_samples, 
                               $ignore_failed, 
                               $ignore_lane_count,
                               $skip_scheduling);
}

sub should_be_scheduled {
    my ($aligns, $force_run, $report_file, $sample, $running_samples, $ignore_failed, $ignore_lane_count, $skip_scheduling) = @_;

    if ($skip_scheduling) {
        say $report_file "\t\tCONCLUSION: SKIPPING SCHEDULING";
        return 1;
    }

    if (unaligned($aligns, $report_file) and not scheduled($report_file, $sample, $running_samples, $force_run, $ignore_failed, $ignore_lane_count) ) { 
        say $report_file "\t\tCONCLUSION: SCHEDULING WORKFLOW FOR THIS SAMPLE!\n";
        return 1;
    }

    say $report_file "\t\tCONCLUSION: WILL NOT SCHEDULE THIS SAMPLE FOR ALIGNMENT!"; 
    return 0;
}

sub unaligned {
    my ($aligns, $report_file) = @_;

    if  ( (scalar keys %{$aligns} == 1 and defined $aligns->{unaligned}) ) {
        say $report_file "\t\tONLY UNALIGNED";
        return 1;
    }
    
    say $report_file "\t\tCONTAINS ALIGNMENT"; 
    return 0; 
}

sub scheduled {
    my ($report_file, $sample, $running_samples, $force_run, $ignore_failed, $ignore_lane_count ) = @_; 

    my $analysis_url_str = join ',', sort keys %{$sample->{analysis_url}};
    $sample->{analysis_url} = $analysis_url_str;
    
    my $sample_id = $sample->{sample_id};

    if (( not exists($running_samples->{$sample_id}) 
        and not exists($running_samples->{$analysis_url_str})) or $force_run) {
        say $report_file "\t\tNOT PREVIOUSLY SCHEDULED OR RUN FORCED!";
    } 
    elsif (( (exists($running_samples->{$sample_id}{failed}) and (scalar keys %{$running_samples->{$sample_id}} == 1)) or ( exists($running_samples->{$analysis_url_str}{failed}) and (scalar keys %{$running_samples->{$analysis_url_str}} == 1))) and $ignore_failed) {
        say $report_file "\t\tPREVIOUSLY FAILED BUT RUN FORCED VIA IGNORE FAILED OPTION!";
    } 
    else {
        say $report_file "\t\tIS PREVIOUSLY SCHEDULED, RUNNING, OR FAILED!";
        say $report_file "\t\t\tSTATUS:".join ',',keys %{$running_samples->{sample_id}};
        return 1;
    }

    if ($sample->{total_lanes} == $sample->{bam_count} || $ignore_lane_count || $force_run) {
        say $report_file "\t\tLANE COUNT MATCHES OR IGNORED OR RUN FORCED: ignore_lane_count: $ignore_lane_count total lanes: $sample->{total_lanes} bam count: $sample->{bams_count}\n";
    } 
    else {
        say $report_file "\t\tLANE COUNT MISMATCH!";
        return 1;
    }

    return 0;
}

1;
