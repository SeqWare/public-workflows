package SeqWare::Schedule::EBI;
# subclass schedule for EBI-specific variant calling workflow

use Data::Dumper;
use parent SeqWare::Schedule;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

sub create_settings_file {
    my $self = shift;
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


#$self->create_settings_file(
#    $donor,
#    $seqware_settings_file,
#    $url,
#    $username,
#    $password,
#    $working_dir,
#    $center_name,
#    $donor_id
#    );

#$self->create_workflow_ini(
#    $donor,
#    $run_workflow_version,
#    $gnos_url,
#    $skip_gtdownload,
#    $skip_gtupload,
#    $upload_results,
#    $output_prefix,
#    $output_dir,
#    $working_dir,
#    $center_name,
#    $donor_id
#    );

sub create_workflow_ini {
    my $self = shift;
    my (
	$workflow_version, 
	$donor, 
	$gnos_url, 
	$threads, 
	$skip_gtdownload, 
	$skip_gtupload, 
	$upload_results, 
	$output_prefix, 
	$output_dir, 
	$working_dir, 
	$center_name, 
	$sample_id) = @_;

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

1;
