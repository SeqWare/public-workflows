package SeqWare::Cluster;

use common::sense;

use IPC::System::Simple;
use autodie qw(:all);

use File::Slurp;

use XML::DOM;
use JSON;
use XML::LibXML;

sub cluster_seqware_information {
    my ($class, $report_file, $json_cluster, $ignore_failed) = @_;

    my $clusters = decode_json( read_file( "conf/$json_cluster" ));

    my $cluster_information = {};
    my $running_samples = {};

    foreach my $cluster_name (keys %{$clusters}) {
        my $cluster_metadata = $clusters->{$cluster_name};
        seqware_information( $report_file,
                             $cluster_name, 
                             $cluster_metadata,
                             $cluster_information,
                             $running_samples);
    }

    return ($cluster_information, $running_samples);
}

sub seqware_information {
    my ($report_file, $cluster_name, $cluster_metadata, 
                                   $cluster_information, $running_samples) = @_;


    my $user = $cluster_metadata->{username};
    my $password = $cluster_metadata->{password};
    my $web = $cluster_metadata->{webservice};
    my $workflow_accession = $cluster_metadata->{workflow_accession};
    my $max_running = $cluster_metadata->{max_workflows};
    my $max_scheduled_workflows = $cluster_metadata->{max_scheduled_workflows};

    $max_running = 1 if ($max_running <= 0 || $max_running eq "");

    $max_scheduled_workflows = $max_running 
          if ($max_scheduled_workflows <= 0 
                  || $max_scheduled_workflows eq "" 
                  || $max_scheduled_workflows > $max_running);

    say $report_file "EXAMINING CLUSER: $cluster_name";

   my $workflow_information = `wget --timeout=60 -t 2 -O - --http-user='$user' --http-password=$password -q $web/workflows/$workflow_accession`;

   my $running = 0;
   if ($workflow_information eq '' ) {
       say "could not connect to cluster: $web";
       return;
   }

   my $dom = XML::LibXML->new->parse_string($workflow_information);
   if ($dom->findnodes('//Workflow/name/text()')) {
       my $workflow_runs = `wget -O - --http-user='$user' --http-password=$password -q $web/workflows/$workflow_accession/runs`;
       my $seqware_runs_domain = XML::LibXML->new->parse_string($workflow_runs);
       $running = find_available_clusters($report_file, $seqware_runs_domain,
                                          $workflow_accession, $running_samples);
   }

   if ($running < $max_running ) {
       say $report_file  "\tTHERE ARE $running RUNNING WORKFLOWS WHICH IS LESS THAN MAX OF $max_running, ADDING TO LIST OF AVAILABLE CLUSTERS";
       for (my $i=0; $i<$max_scheduled_workflows; $i++) {
           $cluster_information->{"$cluster_name\_$i"} = $cluster_metadata;
       }
   } 
   else {
      say $report_file "\tCLUSTER HAS RUNNING WORKFLOWS, NOT ADDING TO AVAILABLE CLUSTERS";
   }
  
   return;
}

sub find_available_clusters {
    my ($report_file, $seqware_runs_domain, $workflow_accession, $run_samples) = @_;

    my $running = 0;
    say $report_file "\tWORKFLOWS ON THIS CLUSTER";
    my $i = 0;
    for my $node ($seqware_runs_domain->findnodes('//WorkflowRunList2/list/status/text()')) {
        $i++;
        say $report_file  "\t\tWORKFLOW: ".$workflow_accession." STATUS: ".$node->toString();
        $running++ if ($node->toString() eq 'pending' 
                         || $node->toString() eq 'running' 
                         || $node->toString() eq 'scheduled' 
                         || $node->toString() eq 'submitted');

        find_running_samples($report_file, $seqware_runs_domain, $run_samples, $i, $node);
     }

     return $running;
}

sub find_running_samples {
    my ($report_file, $seqware_runs_domain, $run_samples, $i, $node) = @_;

    my $j=0;
    my $ini_file =  $seqware_runs_domain->findnodes('//WorkflowRunList2/list/iniFile/text()');

    for my $node2 (@{$ini_file}) {
        $j++;
        my $ini_contents = $node2->toString();
        $ini_contents =~ /gnos_input_metadata_urls=(\S+)/;
        my @urls = split /,/, $1;
        my $sorted_urls = join(",", sort @urls);
        if ($i==$j) { 
             $run_samples->{$sorted_urls} = $seqware_runs_domain->toString(); 
             say $report_file "\t\t\tINPUTS: $sorted_urls";
        }
    }

    my $seqware_working_directories = $seqware_runs_domain->findnodes('//WorkflowRunList2/list/currentWorkingDir/text()');
    my $working_directory_node = $seqware_working_directories->[$i];
    say $report_file "\t\t\tCWD: ".$working_directory_node->toString()
                                              if defined $working_directory_node;

    my $seqware_accessions = $seqware_runs_domain->findnodes('//WorkflowRunList2/list/swAccession/text()');
    my $accession_node = (defined $seqware_accessions->[$i])?
                                                $seqware_accessions->[$i]->toString() : '';
    say $report_file "\t\t\tWORKFLOW ACCESSION: ".$accession_node."\n";

    return;
} 



1;
