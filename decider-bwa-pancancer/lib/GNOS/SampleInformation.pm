package GNOS::SampleInformation;

use common::sense;

use IPC::System::Simple;
use autodie qw(:all);

use Carp::Always;
use File::Slurp;
use Term::ProgressBar;

use XML::Simple qw(:strict);
use Data::Dumper;

sub get {
    my ($class, $working_dir, $gnos_url, $use_live_cached, $use_cached_analysis) = @_;

    system("mkdir -p $working_dir");
    open my $parse_log, '>', "$working_dir/xml_parse.log";

    my $participants = {};

    if ( (not $use_live_cached) || (not -e "$working_dir/xml/data.xml") ) {
        my $cmd = "mkdir -p $working_dir/xml; cgquery -s $gnos_url -o $working_dir/xml/data.xml";
        $cmd .= ($gnos_url =~ /cghub.ucsc.edu/)? " 'study=PAWG&state=live'":" 'study=*&state=live'";

        say $parse_log "cgquery command: $cmd";

        system($cmd);
    }

    my $xs = XML::Simple->new(forcearray => 0, keyattr => 0 );
    my $data = $xs->XMLin("$working_dir/xml/data.xml");

    my $results = $data->{Result};

    say $parse_log '';
    
    my $progress_bar = Term::ProgressBar->new(scalar @$results);
 
    my $i = 0;
    foreach my $result (@{$results}) {
        $progress_bar->update($i++);
        my $analysis_full_url = $result->{analysis_full_uri};
        my $analysis_id = $i;
        if ( $analysis_full_url =~ /^(.*)\/([^\/]+)$/ ) {
            $analysis_full_url = $1."/".lc $2;
            $analysis_id = lc $2;
        } 
        else {
            say $parse_log "SKIPPING: no analysis url";
            next;
        }
        say $parse_log "\n\nANALYSIS\n";
        say $parse_log "\tANALYSIS FULL URL: $analysis_full_url $analysis_id";

        my $analysis_xml_path =  "$working_dir/xml/data_$analysis_id.xml";
        download_analysis($analysis_full_url, $analysis_xml_path, $use_cached_analysis);
         
        if (-e $analysis_xml_path and eval { $xs->XMLin($analysis_xml_path) } ) {

            my $analysis_data = $xs->XMLin($analysis_xml_path); 
            my $analysis_data_result = $analysis_data->{Result};
        
            my $analysis_attributes = $analysis_data_result->{analysis_xml}{ANALYSIS_SET}{ANALYSIS}{ANALYSIS_ATTRIBUTES}{ANALYSIS_ATTRIBUTE};
                
            my %attributes;
            foreach my $attribute (@$analysis_attributes) {
                 $attributes{$attribute->{TAG}} = $attribute->{VALUE};
            }


            my $analysis_data_uri = $analysis_data_result->{analysis_data_uri};
            my $submitter_aliquot_id = $analysis_data_result->{submitter_aliquot_id};
            my $aliquot_uuid = $attributes{aliquot_id};
            my $aliquot_id = $analysis_data_result->{aliquot_id};
            my $submitter_participant_id = $attributes{submitter_participant_id};;
            my $participant_id = $analysis_data_result->{participant_id};
            my $submitter_sample_id = $attributes{submitter_sample_id};
            my $sample_id = $analysis_data_result->{sample_id};  
            my $use_control = $analysis_data_result->{use_cntl};
            my $alignment = $analysis_data_result->{refassem_short_name};
            my $total_lanes = $attributes{total_lanes};
            my $center_name = $analysis_data_result->{center_name};
            my $workflow_version = $attributes{workflow_version};

            my $sample_uuid = $analysis_data_result->{analysis_xml}{ANALYSIS_SET}{ANALYSIS}{TARGETS}{TARGET}{refname};


            my $donor_id = $submitter_participant_id || $participant_id;
            
            say $parse_log "\tDONOR:\t$donor_id";
            say $parse_log "\tANALYSIS:\t$analysis_data_uri";
            say $parse_log "\tANALYSIS ID:\t$analysis_id";
            say $parse_log "\tPARTICIPANT ID:\t$participant_id";
            say $parse_log "\tSAMPLE ID:\t$sample_id";
            say $parse_log "\tALIQUOT ID:\t$aliquot_id";
            say $parse_log "\tSUBMITTER PARTICIPANT ID:\t$submitter_participant_id";
            say $parse_log "\tSUBMITTER SAMPLE ID:\t$submitter_sample_id";
            say $parse_log "\tSUBMITTER ALIQUOT ID:\t$submitter_aliquot_id";
            say $parse_log "\tWORKFLOW VERSION:\t$workflow_version";
    
            next unless (my $library_descriptor = eval { $analysis_data_result->{experiment_xml}{EXPERIMENT_SET}{EXPERIMENT}{DESIGN}{LIBRARY_DESCRIPTOR}});
            my $library_name = $library_descriptor->{LIBRARY_NAME};
            my $library_strategy = $library_descriptor->{LIBRARY_STRATEGY};
            my $library_source = $library_descriptor->{LIBRARY_SOURCE};
            say $parse_log "\tLibrary\n\t\tName:\t$library_name\n\t\tLibrary Strategy:\t$library_strategy\n\t\tLibrary Source:\t$library_source";
    
            if (not $library_name or not $library_strategy or not $library_source or not $analysis_id or not $analysis_data_uri) {
                say $parse_log "\tERROR: one or more critical fields not defined, will skip $analysis_id\n";
                next;
            }
    
            say $parse_log "\tgtdownload -c gnostest.pem -v -d $analysis_data_uri\n";
    
            my $library = {
                         analysis_ids             => $analysis_id,
                         analysis_url             => $analysis_data_uri,
                         library_name             => $library_name,
                         library_strategy         => $library_strategy,
                         library_source           => $library_source,
                         alignment_genome         => $alignment,
                         use_control              => $use_control,
                         total_lanes              => $total_lanes,
                         submitter_participant_id => $submitter_participant_id,
                         sample_id                => $sample_id,
                         submitter_sample_id      => $submitter_sample_id,
                         submitter_aliquot_id     => $submitter_aliquot_id,
                         sample_uuid              => $sample_uuid,
                         workflow_version         => $workflow_version };

            foreach my $attribute (keys %{$library}) {
                my $library_value = $library->{$attribute};
                $participants->{$center_name}{$donor_id}{$sample_uuid}{$alignment}{$aliquot_id}{$library_name}{$attribute}{$library_value} = 1;
            }

            my $files = files($analysis_data_result, $parse_log, $analysis_id);
            foreach my $file_name (keys %$files) {
                my $file_info = $files->{$file_name};
                $participants->{$center_name}{$donor_id}{$sample_uuid}{$alignment}{$aliquot_id}{$library_name}{files}{$file_name} = $file_info;
            }
        }      
    }
    close $parse_log;

    return $participants;
}

sub files {
    my ($results, $parse_log, $analysis_id) = @_;

    say $parse_log "FILES";

    my $files = $results->{files}{file};
    $files = [ $files ] if ref($files) ne 'ARRAY';

    my %files;
    foreach my $file (@{$files}) {
        my $file_name  = $file->{filename};
        
        next if (not $file_name =~ /\.bam$/);

        $files{$file_name}{size} =  $file->{filesize};
        $files{$file_name}{checksum} = $file->{checksum};
        $files{$file_name}{local_path} = "$analysis_id/$file_name";

        say $parse_log "\tFILE: $file_name SIZE: ".$files{$file_name}{size}." CHECKSUM: ".$files{$file_name}{checksum}{content};
        say $parse_log "\tLOCAL FILE PATH: $analysis_id/$file_name";

    }

    return \%files;
}

sub download_analysis {
    my ($url, $out, $use_cached_analysis) = @_;

    if (not -e $out or not $use_cached_analysis) {
        no autodie;
        my $browser = LWP::UserAgent->new();
        my $response = $browser->get($url);
        if ($response->is_success) {
            write_file($out, $response->decoded_content);
        } 
        else {
            say $response->status_line;
        }
    }
}

1;
