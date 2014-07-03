package GNOS::SampleInformation;

use common::sense;

use IPC::System::Simple;
use autodie qw(:all);

use Carp::Always;

use File::Slurp;

use Term::ProgressBar;


use Data::Dumper;

sub get {
    my ($class, $working_dir, $gnos_url, $skip_down, $skip_cached) = @_;

    system("mkdir -p $working_dir");
    open my $settings_file, '>', "$working_dir/xml_parse.log";

    my $participants = {};
    my $parser = new XML::DOM::Parser;

    unless ($skip_down) {
        my $cmd = "mkdir -p $working_dir/xml; cgquery -s $gnos_url -o $working_dir/xml/data.xml";
        $cmd .= ($gnos_url =~ /cghub.ucsc.edu/)? " 'study=PAWG&state=live'":" 'study=*&state=live'";

        say $settings_file "cgquery command: $cmd";

        system($cmd);
    }

    my $data = $parser->parsefile("$working_dir/xml/data.xml");

    # print OUT all HREF attributes of all CODEBASE elements
    my $results = $data->getElementsByTagName("Result");

    say $settings_file '';
    
    say 'Downloading Sample Information from GNOS';
    my $progress_bar = Term::ProgressBar->new($results->getLength);
 
    for (my $i = 0; $i < $results->getLength; $i++) {
        $progress_bar->update($i);
        my $result = $results->item($i);
        my $analysis_full_url = get_value($result, "analysis_full_uri");

        # have to ensure the UUID is lower case, known GNOS issue
        my $analysis_uuid = $i;
        if ( $analysis_full_url =~ /^(.*)\/([^\/]+)$/ ) {
            $analysis_full_url = $1."/".lc $2;
            $analysis_uuid = lc $2;
        } 
        else {
            say $settings_file "SKIPPING: no analysis url";
            next;
        }

        say $settings_file "ANALYSIS FULL URL: $analysis_full_url $analysis_uuid";

        my $out =  "$working_dir/xml/data_$analysis_uuid.xml";
        download($analysis_full_url, $out, $skip_cached) unless ($skip_down);
         
        if (-e $out and eval { $parser->parsefile("$working_dir/xml/data_$analysis_uuid.xml") } ) {
            my $adoc = $parser->parsefile("$working_dir/xml/data_$analysis_uuid.xml");
            my $adoc2 = XML::LibXML->new->parse_file("$working_dir/xml/data_$analysis_uuid.xml");
            my $analysis_id = get_value($adoc, 'analysis_id');
            my $analysis_data_uri = get_value($adoc, 'analysis_data_uri');
            my $submitter_aliquot_id = get_custom_value($adoc2, ['submitter_aliquot_id', 'submitter_sample_id']);
            my $aliquot_uuid = get_value($adoc, 'aliquot_id');
            my $aliquot_id = get_custom_value($adoc2, ['aliquot_id', 'submitter_sample_id']);
            my $submitter_participant_id = get_custom_value($adoc2, ['submitter_participant_id','submitter_donor_id']);
            my $participant_id = get_custom_value($adoc2, ['participant_id', 'submitter_donor_id']);
            my $submitter_sample_id = get_custom_value($adoc2, ['submitter_sample_id']);
    
            # if donor_id defined then dealing with newer XML
            if (defined(get_custom_value($adoc2, ['submitter_donor_id'])) && get_custom_value($adoc2, 'submitter_donor_id') ne '') {
                $submitter_sample_id = get_custom_value($adoc2, ['submitter_specimen_id']);
            }
            my $sample_id = get_custom_value($adoc2, ['sample_id', 'submitter_specimen_id']);
            my $use_control = get_custom_value($adoc2, ['use_cntl']);
            my $alignment = get_value($adoc, "refassem_short_name");
            my $total_lanes = get_custom_value($adoc2, ['total_lanes']);
            my $sample_uuid = get_xpath_attribute($adoc2, "refname", "//ANALYSIS_SET/ANALYSIS/TARGETS/TARGET/\@refname");
    
            say $settings_file "ANALYSIS:  $analysis_data_uri";
            say $settings_file "ANALYSISID: $analysis_id";
            say $settings_file "PARTICIPANT ID: $participant_id";
            say $settings_file "SAMPLE ID: $sample_id";
            say $settings_file "ALIQUOTID: $aliquot_id";
            say $settings_file "SUBMITTER PARTICIPANT ID: $submitter_participant_id";
            say $settings_file "SUBMITTER SAMPLE ID: $submitter_sample_id";
            say $settings_file "SUBMITTER ALIQUOTID: $submitter_aliquot_id";
    
            my $library_name = get_value($adoc, 'LIBRARY_NAME');
            my $library_strategy = get_value($adoc, 'LIBRARY_STRATEGY');
            my $library_source = get_value($adoc, 'LIBRARY_SOURCE');
            say $settings_file "Library Name: $library_name Library Strategy: $library_strategy Library Source: $library_source";
    
            # get files
            # now if these are defined then move onto the next step
            unless (defined($library_name) && defined($library_strategy) && defined($library_source) && defined($analysis_id) && defined($analysis_data_uri)) {
                say $settings_file "ERROR: one or more critical fields not defined, will skip $analysis_id\n";
                next;
            }
    
            say $settings_file "  gtdownload -c gnostest.pem -v -d $analysis_data_uri\n";
    
            our %library;
            my $library =  $participants->{$participant_id}{$sample_id}{$alignment}{$aliquot_id}{$library_name};
    
            $library->{analysis_id}{$analysis_id} = 1;
            $library->{analysis_url}{$analysis_data_uri} = 1;
            $library->{$library_name} = 1;
            $library->{library_strategy}{$library_strategy} = 1;
            $library->{library_source}{$library_source} = 1;
            $library->{alignment_genome}{$alignment} = 1;
            $library->{use_control}{$use_control} = 1;
            $library->{total_lanes}{$total_lanes} = 1;
            $library->{submitter_participant_id}{$submitter_participant_id} = 1;
            $library->{submitter_sample_id}{$submitter_sample_id} = 1;
            $library->{submitter_aliquot_id}{$submitter_aliquot_id} = 1;
            $library->{sample_uuid}{$sample_uuid} = 1;
            # need to add
            # input_bam_paths=9c414428-9446-11e3-86c1-ab5c73f0e08b/hg19.chr22.5x.normal.bam
            # gnos_input_file_urls=https://gtrepo-ebi.annailabs.com/cghub/data/analysis/download/9c414428-9446-11e3-86c1-ab5c73f0e08b
            # gnos_input_metadata_urls=https://gtrepo-ebi.annailabs.com/cghub/metadata/analysisFull/9c414428-9446-11e3-86c1-ab5c73f0e08b
    
            my $files = read_files($adoc);
            say $settings_file "FILE:";
            foreach my $file (keys %{$files}) {
                say $settings_file "  FILE: $file SIZE: ".$files->{$file}{size}." CHECKSUM: ".$files->{$file}{checksum};
                say $settings_file "  LOCAL FILE PATH: $analysis_id/$file";
                $library{files}{$file}{size} = $files->{$file}{size};
                $library{files}{$file}{checksum} = $files->{$file}{checksum};
                $library{files}{$file}{localpath} = "$analysis_id/$file";
            }
        }
    }
    $results->dispose;
    close $settings_file;

    return $participants;
}

sub read_files {
    my ($domain) = @_;

    my $nodes = $domain->getElementsByTagName('file');

    my %files;
    for (my $i = 0; $i < $nodes->getLength; $i++) {
        my $node = $nodes->item($i);
        my $file = get_value($node, 'filename');

        next if ($file =~ /\.bam$/);

        $files{$file}{size} =  get_value($node, 'filesize');
        $files{$file}{checksum} = get_value($node, 'checksum');
    }

    return \%files;
}

sub get_custom_value {
    my ($domain, $keys) = @_;

    for my $node ($domain->findnodes('//ANALYSIS_ATTRIBUTES/ANALYSIS_ATTRIBUTE')) {
        my $i=0;
        for my $current_key ($node->findnodes('//TAG/text()')) {
            $i++;
            my $key_string = $current_key->toString();
            foreach my $key (@{$keys}) {
                if ($key_string eq $key) {
                    my $values = $node->findnodes('//VALUE/text()');
                    my $current_value = $values->[$i];
                    return $current_value->toString() if defined $current_value;
                }
            }
        }
    }
    return '';
}

sub get_xpath_attribute {
    my ($domain, $key, $xpath) = @_;

    for my $node ($domain->findnodes($xpath)) {
      return $node->getValue() if defined $node;
    }

    return '';
}

sub get_value {
    my ($node, $key) = @_;

    if (defined $node 
        && defined $node->getElementsByTagName($key)
        && defined $node->getElementsByTagName($key)->item(0)
        && defined $node->getElementsByTagName($key)->item(0)->getFirstChild
        && defined $node->getElementsByTagName($key)->item(0)->getFirstChild->getNodeValue) {
        return $node->getElementsByTagName($key)->item(0)->getFirstChild->getNodeValue;
    }

    return undef;
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
