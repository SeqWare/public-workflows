package SeqWare::Cluster;

use common::sense;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use IPC::System::Simple;
use autodie qw(:all);
use Carp::Always;

use File::Slurp;

use XML::DOM;
use JSON;
use XML::LibXML;
use XML::Simple;
use Config::Simple;

use Data::Dumper;

sub cluster_seqware_information {
    my ($class, $report_file, $clusters_json, $ignore_failed, $run_workflow_version) = @_;

    my ($clusters, $cluster_file_path);
    foreach my $cluster_json (@{$clusters_json}) {
        $cluster_file_path = "$Bin/../$cluster_json";
        die "file does not exist $cluster_file_path" unless (-f $cluster_file_path);
        my $cluster = decode_json( read_file($cluster_file_path));
         $clusters = {%$clusters, %$cluster};
    }

    my (%cluster_information,
       %running_samples,
       %failed_samples,
       %completed_samples,
       $cluster_info,
       $samples_status_ids);
    foreach my $cluster_name (keys %{$clusters}) {
        my $cluster_metadata = $clusters->{$cluster_name};
        ($cluster_info, $samples_status_ids) 
            = seqware_information( $report_file,
                                   $cluster_name, 
                                   $cluster_metadata,
                                   $run_workflow_version);

        foreach my $cluster (keys %{$cluster_info}) {
           $cluster_information{$cluster} = $cluster_info->{$cluster};
        }

        foreach my $sample_id (keys %{$samples_status_ids->{running}}) {
           $running_samples{$sample_id} = 1;
        }

        foreach my $sample_id (keys %{$samples_status_ids->{failed}}) {
             $failed_samples{$sample_id} = $samples_status_ids->{failed}{$sample_id};
        }

        foreach my $sample_id (keys %{$samples_status_ids->{completed}}) {
             $completed_samples{$sample_id} = $samples_status_ids->{completed}->{$sample_id};
        }
      
    }

    return (\%cluster_information, \%running_samples, \%failed_samples, \%completed_samples);
}

sub seqware_information {
    my ($report_file, $cluster_name, $cluster_metadata, $run_workflow_version) = @_;

    my $user = $cluster_metadata->{username};
    my $password = $cluster_metadata->{password};
    my $web = $cluster_metadata->{webservice};
    my $workflow_accession = $cluster_metadata->{workflow_accession};
    my $max_running = $cluster_metadata->{max_workflows};
    my $max_scheduled_workflows = $cluster_metadata->{max_scheduled_workflows};

    $max_running = 0 if ($max_running eq "");

    $max_scheduled_workflows = $max_running 
          if ( $max_scheduled_workflows eq "" || $max_scheduled_workflows > $max_running);

    say $report_file "EXAMINING CLUSER: $cluster_name";

    my $workflow_information_xml = `wget --timeout=60 -t 2 -O - --http-user='$user' --http-password=$password -q $web/workflows/$workflow_accession`;

    if ($workflow_information_xml eq '' ) {
       say "could not connect to cluster: $web";
       return;
    }

    my $xs = XML::Simple->new(ForceArray => 1, KeyAttr => 1);
    my $workflow_information = $xs->XMLin($workflow_information_xml);

    my $samples_status;
    if ($workflow_information->{name}) {
        my $workflow_runs_xml = `wget -O - --http-user='$user' --http-password=$password -q $web/workflows/$workflow_accession/runs`;
        my $seqware_runs_list = $xs->XMLin($workflow_runs_xml);
        my $seqware_runs = $seqware_runs_list->{list};

        $samples_status = find_available_clusters($report_file, $seqware_runs,
                   $workflow_accession, $samples_status, $run_workflow_version);
    }
    my $running = scalar(keys %{$samples_status->{running}});
    my %cluster_info;
    if ($running < $max_running ) {
        say $report_file  "\tTHERE ARE $running RUNNING WORKFLOWS WHICH IS LESS THAN MAX OF $max_running, ADDING TO LIST OF AVAILABLE CLUSTERS";
        for (my $i=0; $i<$max_scheduled_workflows; $i++) {
            my %cluster_metadata = %{$cluster_metadata};
            $cluster_info{"$cluster_name-$i"} = \%cluster_metadata
                if ($run_workflow_version eq $cluster_metadata{workflow_version});
        }
    } 
    else {
        say $report_file "\tCLUSTER HAS RUNNING WORKFLOWS, NOT ADDING TO AVAILABLE CLUSTERS";
    }

    return (\%cluster_info, $samples_status);
}

sub find_available_clusters {
    my ($report_file, $seqware_runs, $workflow_accession, $samples_status) = @_;

    say $report_file "\tWORKFLOWS ON THIS CLUSTER";
    foreach my $seqware_run (@{$seqware_runs}) {
        my $run_status = $seqware_run->{status}->[0];

        say $report_file "\t\tWORKFLOW: ".$workflow_accession." STATUS: ".$run_status;

        my ($sample_id, $created_timestamp);

     
        if ( ($sample_id, $created_timestamp) = get_sample_info($report_file, $seqware_run))    {

            my $running_status = { 'pending' => 1,   'running' => 1,
                                   'scheduled' => 1, 'submitted' => 1 };
            $running_status = 'running' if ($running_status->{$run_status});
            $samples_status->{$run_status}{$sample_id}{$created_timestamp} = 1;
        }
     }


     return $samples_status;
}

sub  get_sample_info {
    my ($report_file, $seqware_run) = @_;

    my @ini_file =  split "\n", $seqware_run->{iniFile}[0];

    my $created_timestamp = $seqware_run->{createTimestamp}[0];
    my %parameters;
    foreach my $line (@ini_file) {
         my ($parameter, $value) = split '=', $line, 2;
         $parameters{$parameter} = $value;
    }

    my $sample_id = $parameters{sample_id};
   

    my @urls = split /,/, $parameters{gnos_input_metadata_urls};
    say $report_file "\t\t\tSAMPLE: $sample_id";
    my $sorted_urls = join(',', sort @urls);
    say $report_file "\t\t\tINPUTS: $sorted_urls";

    say $report_file "\t\t\tCWD: ".$parameters{currentWorkingDir};
    say $report_file "\t\t\tWORKFLOW ACCESSION: ".$parameters{swAccession}."\n";

    $sample_id //= $sorted_urls; 

    return ($sample_id, $created_timestamp);
} 



1;
