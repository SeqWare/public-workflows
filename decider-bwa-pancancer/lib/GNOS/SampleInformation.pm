package GNOS::SampleInformation;

use common::sense;

use IPC::System::Simple;
use autodie qw(:all);

use FindBin qw($Bin);

use Carp::Always;
use File::Slurp;
#use Term::ProgressBar::Quiet;

use XML::LibXML;
use XML::LibXML::Simple qw(XMLin);
use Data::Dumper;

sub get {
    my ($class, $working_dir, $gnos_url, $use_live_cached, $use_cached_analysis) = @_;

    system("mkdir -p $working_dir");
    open my $parse_log, '>', "$Bin/../$working_dir/xml_parse.log";

    my $participants = {};

    if ( (not $use_live_cached) || (not -e "$Bin/../$working_dir/xml/data.xml") ) {
        my $cmd = "mkdir -p $working_dir/xml; cgquery -s $gnos_url -o $Bin/../$working_dir/xml/data.xml";
        $cmd .= ($gnos_url =~ /cghub.ucsc.edu/)? " 'study=PAWG&state=live'":" 'study=*&state=live'";

        say $parse_log "cgquery command: $cmd";

        system($cmd);
    }

    my $xs = XML::LibXML::Simple->new(forcearray => 0, keyattr => 0 );
    my $data = $xs->XMLin("$Bin/../$working_dir/xml/data.xml");

    my $results = $data->{Result};
   
    say $parse_log '';
    
    #my $progress_bar = Term::ProgressBar::Quiet->new({count => scalar( keys %$results) });
 
    my $i = 0;
    foreach my $result_id (keys %{$results}) {
        my $result = $results->{$result_id};
        #$progress_bar->update($i++);
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
        my $analysis_xml_path =  "$Bin/../$working_dir/xml/data_$analysis_id.xml";
        
        my $status = 0;
        my $attempts = 0;

        while ($status == 0 and $attempts < 10) {
            $status = download_analysis($analysis_full_url, $analysis_xml_path, $use_cached_analysis);
            $attempts++;
        }         

        if (not -e $analysis_xml_path and eval {$xs->XMLin($analysis_xml_path); }) {
           say $parse_log "skipping $analysis_id: no xml file available";
           next;
        } 

        my $analysis_data = $xs->XMLin($analysis_xml_path);

        if (ref($analysis_data) ne 'HASH'){
            say "XML can not be converted to a hash for $analysis_id";
            next;
        }

        my %analysis = %{$analysis_data};
        
        my $analysis_result = $analysis{Result};
        if (ref($analysis_result) ne 'HASH') {
             say $parse_log "XML does not contain Results - not including:$analysis_id";
             next;
        }

        my %analysis_result = %{$analysis_result};      
        my $last_modified = $analysis_result{last_modified};
        my $analysis_xml_path =  "$working_dir/xml/data_$analysis_id.xml";
        my $center_name = $analysis_result{center_name};
        my $analysis_data_uri = $analysis_result{analysis_data_uri};
        my $submitter_aliquot_id = $analysis_result{submitter_aliquot_id};
        my $aliquot_id = $analysis_result{aliquot_id};

        my $participant_id = $analysis_result{participant_id};
        if (ref($participant_id) eq 'HASH') {
            $participant_id = undef;
        }

        my $use_control = $analysis_result{use_cntl};
        my $alignment = $analysis_result{refassem_short_name};
        my $sample_id = $analysis_result{sample_id};
        if (ref($sample_id) eq 'HASH') {
           $sample_id = undef;
        }
        my ($analysis_attributes,$sample_uuid);
        if (ref($analysis_result{analysis_xml}{ANALYSIS_SET}) eq 'HASH'
           and ref($analysis_result{analysis_xml}{ANALYSIS_SET}{ANALYSIS}) eq 'HASH') {
            if (ref($analysis_result{analysis_xml}{ANALYSIS_SET}{ANALYSIS}{ANALYSIS_ATTRIBUTES}) eq 'HASH') {
                $analysis_attributes = $analysis_result{analysis_xml}{ANALYSIS_SET}{ANALYSIS}{ANALYSIS_ATTRIBUTES}{ANALYSIS_ATTRIBUTE};                
            }
            elsif ( ref($analysis_result{analysis_xml}{ANALYSIS_SET}{ANALYSIS}{TARGETS}{TARGETS_ATTRIBUTES}) eq 'HASH'
                 and ref($analysis_result{analysis_xml}{ANALYSIS_SET}{ANALYSIS}{TARGETS}{TARGET}) eq 'HASH') {
                 $sample_uuid = $analysis_result{analysis_xml}{ANALYSIS_SET}{ANALYSIS}{TARGETS}{TARGET}{refname};
            }
        }

        my (%attributes, $total_lanes, $aliquot_uuid, $submitter_participant_id, $submitter_donor_id, 
            $submitter_sample_id, $workflow_version, $submitter_specimen_id, $workflow_name);
        if (ref($analysis_attributes) eq 'ARRAY') {
            foreach my $attribute (@$analysis_attributes) {
                $attributes{$attribute->{TAG}} = $attribute->{VALUE};
            }

            $total_lanes = $attributes{total_lanes};
            $aliquot_uuid = $attributes{aliquot_id};
            $submitter_participant_id = $attributes{submitter_participant_id};
            $submitter_participant_id = undef if (ref($submitter_participant_id) eq 'HASH');

            $submitter_donor_id = $attributes{submitter_donor_id};
            $submitter_donor_id = undef if (ref($submitter_donor_id) eq 'HASH');

            $submitter_sample_id = $attributes{submitter_sample_id};
            $submitter_sample_id = undef if (ref($submitter_sample_id) eq 'HASH');

            $submitter_specimen_id = $attributes{submitter_specimen_id};
            $submitter_specimen_id = undef if (ref($submitter_specimen_id) eq 'HASH');
            $workflow_version = $attributes{workflow_version};
            $workflow_name = $attributes{workflow_name};
        }

        my $donor_id = $submitter_participant_id || $participant_id;
        
        say $parse_log "\tDONOR:\t$donor_id";
        say $parse_log "\tANALYSIS:\t$analysis_data_uri";
        say $parse_log "\tANALYSIS ID:\t$analysis_id";
        say $parse_log "\tPARTICIPANT ID:\t$participant_id";
        say $parse_log "\tSAMPLE ID:\t$sample_id";
        say $parse_log "\tALIQUOT ID:\t$aliquot_id";
        say $parse_log "\tSUBMITTER PARTICIPANT ID:\t$submitter_participant_id";
        say $parse_log "\tSUBMITTER DONOR ID:\t$submitter_donor_id";
        say $parse_log "\tSUBMITTER SAMPLE ID:\t$submitter_sample_id";
        say $parse_log "\tSUBMITTER ALIQUOT ID:\t$submitter_aliquot_id";
        say $parse_log "\tWORKFLOW VERSION:\t$workflow_version";

        my ($library_name, $library_strategy, $library_source);
        my $library_descriptor;
        if (exists ($analysis_result{experiment_xml})) {

             if (ref($analysis_result{experiment_xml}{EXPERIMENT_SET}{EXPERIMENT}) eq 'HASH') {
                 $library_descriptor = $analysis_result{experiment_xml}{EXPERIMENT_SET}{EXPERIMENT}{DESIGN}{LIBRARY_DESCRIPTOR};
             }
             else {
                 $library_descriptor = $analysis_result{experiment_xml}{EXPERIMENT_SET}{EXPERIMENT}[0]{DESIGN}{LIBRARY_DESCRIPTOR};
             }
        }         
        my %library = (ref($library_descriptor) == 'HASH')? %{$library_descriptor} : ();
        my $library_name = $library{LIBRARY_NAME};
        my $library_strategy = $library{LIBRARY_STRATEGY};
        my $library_source = $library{LIBRARY_SOURCE};

        say $parse_log "\tLibrary\n\t\tName:\t$library_name\n\t\tLibrary Strategy:\t$library_strategy\n\t\tLibrary Source:\t$library_source";

        if (not $library_name or not $library_strategy or not $library_source or not $analysis_id or not $analysis_data_uri) {
            say $parse_log "\tERROR: one or more critical fields not defined, will skip $analysis_id\n";
            next;
        }

        say $parse_log "\tgtdownload -c gnostest.pem -v -d $analysis_data_uri\n";

        #This takes into consideration the files that were submitted with the old SOP
        $sample_id //= $submitter_specimen_id;
        $submitter_participant_id //= $submitter_donor_id;
        $aliquot_id //= $submitter_sample_id;           
        $submitter_aliquot_id //= $submitter_sample_id;
        $sample_uuid //= $sample_id;
        $center_name //= 'unknown';

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

        $center_name = 'seqware';
        if ($alignment ne 'unaligned') { 
            $alignment = "$alignment-$analysis_id-$workflow_name-$workflow_version-$last_modified";
        }

        foreach my $attribute (keys %{$library}) {
            my $library_value = $library->{$attribute};
            $participants->{$center_name}{$donor_id}{$sample_uuid}{$alignment}{$aliquot_id}{$library_name}{$attribute}{$library_value} = 1;
        }

        my $files = files($analysis_result, $parse_log, $analysis_id);
        foreach my $file_name (keys %$files) {
            my $file_info = $files->{$file_name};
            $participants->{$center_name}{$donor_id}{$sample_uuid}{$alignment}{$aliquot_id}{$library_name}{files}{$file_name} = $file_info;
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

    my $parser   = XML::LibXML->new();

    return 1   if (-e $out and eval{$parser->parse_string(read_file($out))} 
                                                      and $use_cached_analysis);
    no autodie;
    my $browser = LWP::UserAgent->new();
    $browser->timeout(300);#seconds: 5 minutes
    my $response = $browser->get($url);
    if ($response->is_success) {
       if (eval { $parser->parse_string($response->decoded_content); }) {
           write_file($out, $response->decoded_content);
           return 1;
       }
       else {
           return 0;
       }
    }
 
    say $response->status_line;
    
    return 0;
}

1;
