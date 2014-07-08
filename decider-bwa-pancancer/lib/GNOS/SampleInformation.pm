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
    my ($class, $working_dir, $gnos_url, $skip_down, $skip_cached) = @_;

    system("mkdir -p $working_dir");
    open my $parse_log, '>', "$working_dir/xml_parse.log";

    my $participants = {};

    if ($skip_down == 0) {
        my $cmd = "mkdir -p $working_dir/xml; cgquery -s $gnos_url -o $working_dir/xml/data.xml";
        $cmd .= ($gnos_url =~ /cghub.ucsc.edu/)? " 'study=PAWG&state=live'":" 'study=*&state=live'";

        say $parse_log "cgquery command: $cmd";

        system($cmd);
    }

    my $xs = XML::Simple->new(forcearray => 0, keyattr => 0 );
    my $data = $xs->XMLin("$working_dir/xml/data.xml");

    my $results = $data->{Result};

    say $parse_log '';
    
    say 'Downloading Sample Information from GNOS';

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

        say $parse_log "ANALYSIS FULL URL: $analysis_full_url $analysis_id";

        my $analysis_xml_path =  "$working_dir/xml/data_$analysis_id.xml";
        download($analysis_full_url, $analysis_xml_path, $skip_cached) unless ($skip_down);
         
        if (-e $analysis_xml_path and eval { $xs->XMLin($analysis_xml_path) } ) {
            my $analysis_data = $xs->XMLin($analysis_xml_path); 
            my $analysis_data_result = $analysis_data->{Result};
            my $analysis_data_uri = $analysis_data_result->{analysis_data_uri};
            my $submitter_aliquot_id = $analysis_data_result->{submitter_aliquot_id};
            my $aliquot_uuid = $analysis_data_result->{aliquot_id};
            my $aliquot_id = $analysis_data_result->{aliquot_id};
            my $submitter_participant_id = $analysis_data_result->{submitter_participant_id};;
            my $participant_id = $analysis_data_result->{participant_id};
            my $submitter_sample_id = $analysis_data_result->{submitter_sample_id};
            my $sample_id = $analysis_data_result->{sample_id};
            my $use_control = $analysis_data_result->{use_cntl};
            my $alignment = $analysis_data_result->{refassem_short_name};
            my $total_lanes = $analysis_data_result->{total_lanes};
            my $center_name = $analysis_data_result->{center_name};

            my $sample_uuid = $analysis_data_result->{analysis_xml}{ANALYSIS_SET}{ANALYSIS}{TARGETS}{TARGET}{refname};

            say $parse_log "ANALYSIS:  $analysis_data_uri";
            say $parse_log "ANALYSISID: $analysis_id";
            say $parse_log "PARTICIPANT ID: $participant_id";
            say $parse_log "SAMPLE ID: $sample_id";
            say $parse_log "ALIQUOT ID: $aliquot_id";
            say $parse_log "SUBMITTER PARTICIPANT ID: $submitter_participant_id";
            say $parse_log "SUBMITTER SAMPLE ID: $submitter_sample_id";
            say $parse_log "SUBMITTER ALIQUOTID: $submitter_aliquot_id";
    
            next unless (my $library_descriptor = eval { $analysis_data_result->{experiment_xml}{EXPERIMENT_SET}{EXPERIMENT}{DESIGN}{LIBRARY_DESCRIPTOR}});
            my $library_name = $library_descriptor->{LIBRARY_NAME};
            my $library_strategy = $library_descriptor->{LIBRARY_STRATEGY};
            my $library_source = $library_descriptor->{LIBRARY_SOURCE};
            say $parse_log "Library\tName:\t$library_name\n\t\tLibrary Strategy:\t$library_strategy\n\t\tLibrary Source:\t$library_source";
    
            if (not $library_name or not $library_strategy or not $library_source or not $analysis_id or not $analysis_data_uri) {
                say $parse_log "ERROR: one or more critical fields not defined, will skip $analysis_id\n";
                next;
            }
    
            say $parse_log "  gtdownload -c gnostest.pem -v -d $analysis_data_uri\n";
    
            my %library;
            $library{analysis_id}{$analysis_id} = 1;
            $library{analysis_url}{$analysis_data_uri} = 1;
            $library{library_name}{$library_name} = 1;
            $library{library_strategy}{$library_strategy} = 1;
            $library{library_source}{$library_source} = 1;
            $library{alignment_genome}{$alignment} = 1;
            $library{use_control}{$use_control} = 1;
            $library{total_lanes}{$total_lanes} = 1;
            $library{submitter_participant_id}{$submitter_participant_id} = 1;
            $library{sample_id}{$sample_id} = 1;
            $library{submitter_sample_id}{$submitter_sample_id} = 1;
            $library{submitter_aliquot_id}{$submitter_aliquot_id} = 1;
            $library{sample_uuid}{$sample_uuid} = 1;    
            $library{files} = files($analysis_data, $parse_log, $analysis_id);

            $participants->{$center_name}{$participant_id}{$sample_uuid}{$alignment}{$aliquot_id}{$library_name} = \%library;

        }      
    }

    close $parse_log;

    return $participants;
}

sub files {
    my ($results, $parse_log, $analysis_id) = @_;

    say $parse_log "FILE:";

    my $files = $results->{files};

    my %files;
    foreach my $file (@$files) {
        my $file_name  = $files->{file}{filename};

        next if (not $file_name =~ /\.bam$/);

        $files{$file_name}{size} =  $files->{file}{filesize};
        $files{$file_name}{checksum} = $files->{file}{checksum};
        $files{$file_name}{localpath} = "$analysis_id/$file";

        say $parse_log "  FILE: $file SIZE: ".$files{$file}{size}." CHECKSUM: ".$files{$file}{checksum};
        say $parse_log "  LOCAL FILE PATH: $analysis_id/$file";

    }

    return \%files;
}

sub download {
    my ($url, $out, $skip_cached) = @_;

    if (not -e $out or not $skip_cached) {
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
