#!/usr/bin/perl
#
# File: pcap_data_freeze_2.0_NEW_report_generator.pl
# 
# based on, and forked from my previous script 
# named: pcap_data_freeze_2.0_alt_report_generator.pl
#
# This NEW version is a NEW fork designed to address Lincoln's requests for
# a specific way of treating the specimens (instead of putting the T/N pairs
# on the same line)
# 
# Last Modified: 2014-08-24, Status: basically working

use strict;
use warnings;
use XML::DOM;
use Data::Dumper;
use Getopt::Long;
use XML::LibXML;
use Cwd;
use Carp;

# globally overriding calls to die, and sending them to Carp
# as shown by brian d foy on page 50 in Mastering Perl

$SIG{__DIE__} = sub { &Carp::confess };

#############
# VARIABLES #
#############
my $error_log = 0;
my $skip_down = 0;
my $gnos_url = q{};
my $xml_file = undef;
my $uri_list = undef;

my @repos = qw( bsc cghub dkfz ebi etri osdc osdc_icgc osdc_tcga riken );

my %urls = ( bsc   => "https://gtrepo-bsc.annailabs.com",
             cghub => "https://cghub.ucsc.edu",
             dkfz  => "https://gtrepo-dkfz.annailabs.com",
             ebi   => "https://gtrepo-ebi.annailabs.com",
             etri  => "https://gtrepo-etri.annailabs.com",
             osdc  => "https://gtrepo-osdc.annailabs.com",
             osdc_icgc  => "https://gtrepo-osdc-icgc.annailabs.com",
             osdc_tcga  => "https://gtrepo-osdc-tcga.annailabs.com",
             riken => "https://gtrepo-riken.annailabs.com",
);

my %analysis_ids = ();
my %sample_uuids = ();
my %aliquot_ids = ();
my %tum_aliquot_ids = ();
my %norm_aliquot_ids = ();
my %norm_use_cntls = ();
my %use_cntls = ();
my %bams_seen = ();
my %problems = ();
my $single_specimens = {};
my $paired_specimens = {};
my $many_specimens = {};

my %study_names = ( 'BLCA-US' => "Bladder Urothelial Cancer - TGCA, US",
                    'BOCA-UK' => "Bone Cancer - Osteosarcoma / chondrosarcoma / rare subtypes",
                    'BRCA-EU' => "Breast Cancer - ER+ve, HER2-ve",
                    'BRCA-US' => "Breast Cancer - TCGA, US",
                    'BRCA-UK' => "Breast Cancer - Triple Negative/lobular/other",
                    'BTCA-SG' => "Biliary tract cancer - Gall bladder cancer / Cholangiocarcinoma",
                    'CESC-US' => "Cervical Squamous Cell Carcinoma - TCGA, US",
                    'CLLE-ES' => "Chronic Lymphocytic Leukemia - CLL with mutated and unmutated IgVH",
                    'CMDI-UK' => "Chronic Myeloid Disorders - Myelodysplastic Syndromes, Myeloproliferative Neoplasms \& Other Chronic Myeloid Malignancies",
                    'COAD-US' => "Colon Adenocarcinoma - TCGA, US",
                    'EOPC-DE' => "Prostate Cancer - Early Onset",
                    'ESAD-UK' => "Esophageal adenocarcinoma",
                    'GACA-CN' => "Gastric Cancer - Intestinal- and diffuse-type",
                    'GBM-US'  => "Brain Glioblastoma Multiforme - TCGA, US",
                    'HNSC-US' => "Head and Neck Squamous Cell Carcinoma - TCGA, US",
                    'KICH-US' => "Kidney Chromophobe - TCGA, US",
                    'KIRC-US' => "Kidney Renal Clear Cell Carcinoma - TCGA, US",
                    'KIRP-US' => "Kidney Renal Papillary Cell Carcinoma - TCGA, US",
                    'LAML-KR' => "Blood cancer - Acute myeloid leukaemia", 
                    'LAML-US' => "Acute Myeloid Leukemia - TCGA, US",
                    'LGG-US'  => "Brain Lower Grade Gliona - TCGA, US",
                    'LICA-FR' => "Liver Cancer - Hepatocellular carcinoma",
                    'LIHC-US' => "Liver Hepatocellular carcinoma - TCGA, US",
                    'LIRI-JP' => "Liver Cancer - Hepatocellular carcinoma (Virus associated)",
                    'LUAD-US' => "Lung Adenocarcinoma - TCGA, US",
                    'MALY-DE' => "Malignant Lymphoma",
                    'ORCA-IN' => "Oral Cancer - Gingivobuccal",
                    'OV-AU'   => "Ovarian Cancer - Serous cystadenocarcinoma",
                    'OV-US'   => "Ovarian Serous Cystadenocarcinoma - TCGA, US",
                    'PACA-AU' => "Pancreatic Cancer - Ductal adenocarcinoma",
                    'PACA-CA' => "Pancreatic Cancer - Ductal adenocarcinoma - CA",
                    'PAEN-AU' => "Pancreatic Cancer - Endocrine neoplasms",
                    'PBCA-DE' => "Pediatric Brain Tumors",
                    'PRAD-CA' => "Prostate Cancer - Adenocarcinoma; Prostate Adenocarcinoma",
                    'PRAD-UK' => "Prostate Cancer - Adenocarcinoma",
                    'PRAD-US' => "Prostate Adenocarcinoma - TCGA, US",
                    'READ-US' => "Rectum Adenocarcinoma - TCGA, US",
                    'SARC-US' => "Sarcoma - TCGA, US",
                    'SKCM-US' => "Skin Cutaneous melanoma - TCGA, US",
                    'STAD-US' => "Gastric Adenocarcinoma - TCGA, US",
                    'THCA-US' => "Head and Neck Thyroid Carcinoma - TCGA, US",
                    'UCEC-US' => "Uterine Corpus Endometrial Carcinoma- TCGA, US",
);

GetOptions("gnos-url=s" => \$gnos_url, "xml-file=s" => \$xml_file, "skip-meta-download" => \$skip_down, "uri-list=s" => \$uri_list, );

my $usage = "USAGE: There are two ways to runs this script:\nEither provide the name of an XML file on the command line:\n$0 --xml-file <data.xml> --gnos-url <repo>\n OR provide the name of a file that contains a list of GNOS repository analysis_full_uri links:\n$0 --uri-list <list.txt> --gnos-url <repo>.\n\nThe script will also generate this message if you provide both an XML file AND a list of URIs\n";

die $usage unless $xml_file or $uri_list;
die $usage if $xml_file and $uri_list;
die $usage unless $gnos_url;

##############
# MAIN STEPS #
##############
print STDERR scalar localtime, "\n\n";
#print scalar localtime, "\n\n";

my @now = localtime();
my $timestamp = sprintf("%04d_%02d_%02d_%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1],);

# STEP 1. READ INFO FROM GNOS
my $sample_info = read_sample_info();

# STEP 2. MAP SAMPLES
# Process the data structure that has been passed in and print out
# a table showing the donors, specimens, samples, number of bam files, alignment
# status, etc.
map_samples($sample_info);

# STEP 3. QC
# if any errors were detected during the run, notify the user
if ( $error_log ) {
    print STDERR "WARNING: Logged $error_log errors in ${gnos_url}_data_freeze_2.0_NEW_error_log.txt stamped with $timestamp\n";
}
else {
    print STDERR "NO ERRORS FOUND: Apparently no errors were detected while processing $gnos_url\n";
}

END {
    no integer;
    printf( STDERR "Running time: %5.2f minutes\n",((time - $^T) / 60));
    #printf( "Running time: %5.2f minutes\n",((time - $^T) / 60));
} # close END block

###############
# SUBROUTINES #
###############

sub map_samples {
    die "\$sample_info hashref is empty!" unless ($sample_info);
    foreach my $project (sort keys %{$sample_info}) {
        if ( $project ) {
            print STDERR "Now processing XML files for $project\n";
        }
        # Parse the data structure built from all of the XML files, and parse them out
        # into three categories--and three new data structures
        foreach my $donor ( keys %{$sample_info->{$project}} ) {
            my %types = ();
            my @specimens = keys %{$sample_info->{$project}{$donor}};
            foreach my $specimen ( @specimens ) {
                foreach my $sample ( keys %{$sample_info->{$project}{$donor}{$specimen}} ) {
                    my $type = $sample_info->{$project}{$donor}{$specimen}{$sample}{type};
                    push @{$types{$type}}, $specimen unless ( grep {/$specimen/} @{$types{$type}} );
		} # close sample foreach loop
	    } # close specimen foreach loop
            $sample_info->{$project}{$donor} = { specimens => \%{$sample_info->{$project}{$donor}},
                                                 types => \%types,
                                               };
            my $unpaired = 0;
            my $paired = 0;
            my $many_normals = 0;
            if ( scalar keys %types == 1 ) {
                $unpaired = 1;
	    }
            else {
                $paired = 1;
	    }
            foreach my $type ( keys %types ) {
                if ( $type eq 'Normal' ) {
                    if ( scalar( @{$types{$type}} > 1 ) ) {
                        $many_normals = 1;
                    } 
		}
	    } # close inner foreach loop
            # print "\n", Data::Dumper->new([\$sample_info],[qw(sample_info)])->Indent(1)->Quotekeys(0)->Dump, "\n";
            # exit;
            # print "\n", Data::Dumper->new([\%types],[qw(types)])->Indent(1)->Quotekeys(0)->Dump, "\n";
            # These are exclusive tests, so test the worse case first
	    if ( $many_normals ) {
                log_error( "Found more than two Normal specimens for this donor: $donor" );
                $many_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};
	    }
            elsif ( $paired ) {
                $paired_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};      
	    }
            elsif ( $unpaired ) {
                $single_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};
            } 
            else {
                # No specimens, skip it
                log_error( "No specimens found for Project: $project Donor: $donor SKIPPING" );
                next;
	    }
	} # close foreach $donor
    } # close foreach project

    # print "\n", Data::Dumper->new([\$sample_info],[qw(sample_info)])->Indent(1)->Quotekeys(0)->Dump, "\n";
    # exit;

    # At this point all of the data parsed from the xml files should be allocated into
    # one of these three hash references (unless the specimen field was blank
    # Test each hash reference to see if it contains any data, if it does
    # then use the process_specimens subroutine to extract that data into a table
    # and print out each table into individual files:
    if ( keys %{$single_specimens} ) {
        open my $FH1, '>', "$gnos_url" . '_unpaired_specimen_alignments_excluded_' . $timestamp . '.tsv' or die;
        process_specimens( $single_specimens, $FH1, );
        close $FH1;
    }

    if ( keys %{$paired_specimens} ) {
        open my $FH2, '>', "$gnos_url" . '_paired_data_freeze_2.0_table_' . $timestamp . '.tsv' or die;
        process_specimens( $paired_specimens, $FH2, );
        close $FH2;
    }

    if ( keys %{$many_specimens} ) {
        open my $FH3, '>', "$gnos_url" . '_many_Normal_specimen_alignments_excluded_' . $timestamp . '.tsv' or die;
        process_specimens( $many_specimens, $FH3, );
        close $FH3;
    }
} # close sub

sub process_specimens {
    my $sample_info = shift @_;
#    print "\n", Data::Dumper->new([\$sample_info],[qw(sample_info)])->Indent(1)->Quotekeys(0)->Dump, "\n";
#    exit;
    my $FH = shift @_;
    my $endpoint = $urls{$gnos_url};

    print $FH "Study\tProject Code\tDonor ID\tSpecimen/Sample ID\tSample/Aliquot ID\tAnalyzed Sample/Aliquot GUUID\tGNOS endpoint\tType\n";
    foreach my $project (sort keys %{$sample_info}) {
        my $study = $study_names{$project};
        $study = "NO STUDY FOUND" unless $study;     
        foreach my $donor ( keys %{$sample_info->{$project}} ) {
            foreach my $specimen ( keys %{$sample_info->{$project}{$donor}{specimens}} ) {
                foreach my $sample ( keys %{$sample_info->{$project}{$donor}{specimens}->{$specimen}} ) {
                    my $aliquot = $sample_info->{$project}{$donor}{specimens}->{$specimen}{$sample}->{aliquot_id};
                    my $sample_uuid = $sample_info->{$project}{$donor}{specimens}->{$specimen}{$sample}->{sample_uuid};
                    my $type = $sample_info->{$project}{$donor}{specimens}->{$specimen}{$sample}->{type};
                    print $FH "$study\t$project\t$donor\t$specimen\t$sample\t$sample_uuid\t$endpoint\t$type\n";
 	        } # close foreach my $sample
	    } # close foreach my $specimen
	} # close foreach my donor
    } # close foreach my project
} # close sub

sub read_sample_info {
    my $d = {};
    my $type = q{};
    my @uris = ();
    my $doc; 

    # PARSE XML
    my $parser = new XML::DOM::Parser;
    my $parser2 = XML::LibXML->new;
    if ( $xml_file ) {
        print STDERR "Now parsing $xml_file\n";
        # read in the xml file returned by the cgquery command
        $doc = $parser->parsefile("$xml_file");
        my $nodes = $doc->getElementsByTagName ("Result");
        my $n = $nodes->getLength;

        # extract the URIs from the data.xml file
        for ( my $i = 0; $i < $n; $i++ ) {
            my $node = $nodes->item ($i);
            my $aurl = getVal($node, "analysis_full_uri"); 
            if ( $aurl =~ /^(.*)\/([^\/]+)$/ ) {
                $aurl = $1."/".lc($2);
            } 
            push @uris, $aurl;
        }
        $doc->dispose;
        print STDERR "Finished. analysis_full_uris extracted\n";
    }
    elsif ( $uri_list ) {
        open my $URIS, '<', $uri_list or die "Could not open $uri_list for reading!";
        @uris = <$URIS>;
        chomp( @uris );
        close $URIS;
    }
    print STDERR "Entering foreach my \$uri loop\n";
    foreach my $uri ( @uris ) {
        my ( $id ) = $uri =~ m/analysisFull\/([\w-]+)$/;
        print STDERR "Processing $id, checking for files\n";
        # select the skip download option and the script will just use 
        # the Result XML files that were previously downloaded
        if ($skip_down) { 
            print STDERR "Skipping download, using previously downloaded xml/${id}_${gnos_url}.xml\n";
        }
        elsif ( -e "xml/${id}_${gnos_url}.xml" ) {
            print STDERR "Detected a previous copy of xml/${id}_${gnos_url}.xml and will use that\n";
	}
        else {
            print STDERR "Now downloading file ${id}_${gnos_url}.xml from $uri\n";
            download($uri, "xml/${id}_${gnos_url}.xml"); 
        } 
        my $adoc = undef;
        my $adoc2 = undef;

        print STDERR "Checking if download was good for $id\n";
        # test to see if the download and everything worked
        if ( -e "xml/${id}_${gnos_url}.xml" ) {
            # test for file contents to avoid XML parsing errors that kill script
            if ( -z "xml/${id}_${gnos_url}.xml" ) {
                print STDERR "This XML file has zero size (i.e., is empty): ${id}_${gnos_url}.xml\n    SKIPPING\n\n";
                log_error( "SKIPPING xml file is empty and has zero size: ${id}_${gnos_url}.xml" );
                next;
	    }
        
            # create an XML::DOM object:
            $adoc = $parser->parsefile ("xml/${id}_${gnos_url}.xml");
            # create ANOTHER XML::DOM object, using a different Perl library
            # $adoc2 = XML::LibXML->new->parse_file("xml/${id}_${gnos_url}.xml");
            $adoc2 = $parser2->parse_file("xml/${id}_${gnos_url}.xml");
            #print STDERR "Created two new DOM objects for $id\n";
	}
        else {
            print STDERR "Could not find this xml file: ${id}_${gnos_url}.xml\n    SKIPPING\n\n";
            log_error( "SKIPPING Could not find xml file: ${id}_${gnos_url}.xml" );
            next;
	}

      # for Data Freeze Train 2.0 we are only interested in unaligned bams
      # so we are not tabulating anything else in this gnos repo
      my $alignment = getVal($adoc, "refassem_short_name");
      next unless ( $alignment eq 'unaligned' );
      my $project = getCustomVal($adoc2, 'dcc_project_code');
      next unless checkvar( $project, 'project', $id, );
      my $donor_id = getCustomVal($adoc2, 'submitter_donor_id');
      next unless checkvar( $donor_id, 'donor_id', $id, );
      my $specimen_id = getCustomVal($adoc2, 'submitter_specimen_id');
      next unless checkvar( $specimen_id, 'specimen_id', $id, );
      my $sample_id = getCustomVal($adoc2, 'submitter_sample_id');
      next unless checkvar( $sample_id, 'sample_id', $id, );
      my $analysis_id = getVal($adoc, 'analysis_id');
      my $analysisDataURI = getVal($adoc, 'analysis_data_uri');
      # my $submitterAliquotId = getCustomVal($adoc2, 'submitter_aliquot_id');
      my $submitterAliquotId = getVal($adoc, 'submitter_aliquot_id');
      # my $aliquot_id = getVal($adoc, 'aliquot_id');
      # next unless checkvar( $aliquot_id, 'aliquot_id', $id, );
      my $use_control = getCustomVal($adoc2, "use_cntl");
      next unless checkvar( $use_control, 'use_control', $id, );
      # make sure that you are comparing lc vs lc (but not for the Normal samples)
      $use_control = lc($use_control) unless $use_control =~ m/N\/A/;
      my $dcc_specimen_type = getCustomVal($adoc2, 'dcc_specimen_type');
      next unless checkvar( $dcc_specimen_type, 'dcc_specimen_type', $id, );
      my $sample_uuid = getXPathAttr($adoc2, "refname", "//ANALYSIS_SET/ANALYSIS/TARGETS/TARGET/\@refname");
      my $study = getVal($adoc, 'study');
      my $aliquot_id;
      # Test if this XML file is for a TCGA dataset
      if ( $study eq 'PAWG' ) {
          # TCGA datasets use that analysis_id instead of the aliquot_id
          # to identify the correct paired Normal dataset
          $aliquot_id = $analysis_id;
      }
      else {
          $aliquot_id = getVal($adoc, 'aliquot_id');
      }
      next unless checkvar( $aliquot_id, 'aliquot_id', $id, );

      # in the data structure each Analysis Set is sorted by it's ICGC DCC project code, then the combination of
      # donor, specimen, and sample that should be unique identifiers

      $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{analysis_url} = $analysisDataURI; 
      $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{use_control} = $use_control; 
      $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{sample_uuid} = $sample_uuid;
      $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{analysis_id} = $analysis_id;
      $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{aliquot_id} = $aliquot_id;

      # Check to see what is in use_control. If it is N/A then this is a Normal sample
      if ( $use_control && $use_control ne 'N/A' ) {
            # if it passes the test then it must be a 'Tumour', so we give it a 'type'
            # 'type' = 'Tumour'
            $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{type} = 'Tumour';
            # Now lets check to see if this type matches the contents of the dcc_specimen_type
            if ( $dcc_specimen_type =~ m/Normal/ ) {
                log_error( "MISMATCH dcc_specimen type in $id.xml OVERRIDING from Tumour to Normal" );            
                $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{type} = 'Normal';
            }            
            # keep track of the correct use_cntl for this Tumour Sample by storing
            # this information in the %use_cntls hash, where the hash key is the 
            # aliquot_id for this sample, and the hash value is the use_cntl for
            # this sample, extracted from the XML files
            $use_cntls{$aliquot_id} = $use_control;
            # add the aliquot_id to a list of the all the Tumour Aliquot IDs
            $tum_aliquot_ids{$aliquot_id}++;
            # add the aliquot_id specified as the Normal control to a list of all
            # the Normal aliquot IDs that get extracted from all the XML files
            $norm_use_cntls{$use_control}++;
        }
        else {
            # otherwise, this is not a Tumour, so we give it a 'type'
            # 'type' = Normal
            $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{type} = 'Normal';
            # Now lets check to see if this type matches the contents of the dcc_specimen_type
            if ( $dcc_specimen_type =~ m/tumour/ ) {
                log_error( "MISMATCH dcc_specimen type in $id.xml OVERRIDING from Normal to Tumour" );            
                $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{type} = 'Tumour';
            }            
            # Add this aliquot ID to this list of all the 'Normal' 
            # aliquot ids encountered in this XML
            $norm_aliquot_ids{$aliquot_id}++;
        }
        print STDERR "Finished parsing xml and building data structure for $id\n";
        $doc->dispose;
    } # close foreach loop
    return($d);
} # close sub

# My "NEW" Version, from 2014-07-30
sub getCustomVal {
    my ( $dom2, $keys, ) = @_;
    # in a previous incarnation it was useful to iterate
    # over a list of keys that could be sent in
    my @keys_arr = split /,/, $keys;
    # this method call returns an array of XML::LibXML::Elements
    my @nodes = ($dom2->findnodes('//ANALYSIS_ATTRIBUTES/ANALYSIS_ATTRIBUTE'));
    unless ( scalar( @nodes ) > 0 ) {
        log_error( "Could not find any DOM nodes matching ANALYSIS_ATTRIBUTES    SKIPPING" );
        return 0;
    }
    # Examination and testing revealed that all of these Element nodes are equivalent
    # for the next step so we don't need to loop over them 
    # this also returns an array but this time it is an array of XML::LibXML::Text objects
    my @currKeys = ($nodes[0]->findnodes('//TAG/text()')); 
    @currKeys = map { $_->toString() } @currKeys;

    # these TAG => VALUE are paired up like a hash, so lets 
    # convert them into one
    my @currVals = ($nodes[0]->findnodes('//VALUE/text()'));
    @currVals = map { $_->toString() } @currVals;

    # First, check to see if there are an equal number of keys and values
    # because if there are not then that means one of the value fields is 
    # probably blank, an ERROR we'd like to catch now
    unless ( scalar( @currKeys ) == scalar( @currVals ) ) {
        log_error( "Number of Keys does not match number of values in an XML file: missing/blank values?" );
        return 0;
    }
    
    unless ( grep { /$keys_arr[0]/ } @currKeys ) {
        log_error( "This DOM node does not contain the XML element you requested: $keys_arr[0]    SKIPPING" );
        return 0;
    }

    # check for duplicated <TAG>s
    if ( 1 < grep { /$keys_arr[0]/ } @currKeys ) {
        log_error( "This XML file contains more than 1 $keys_arr[0] <TAG>    SKIPPING" );
        return 0;
    }

    my %analysis_attributes;
    for my $i ( 0..$#currKeys ) {
        $analysis_attributes{$currKeys[$i]} = $currVals[$i];
    }

    if ( $analysis_attributes{$keys_arr[0]} ) {
        return $analysis_attributes{$keys_arr[0]};
    }
    else {
        log_error( "The VALUE corresponding to the $keys_arr[0] TAG is false    SKIPPING" );
        return 0;
    }
} # close sub

sub getXPathAttr {
  my ($dom, $key, $xpath) = @_;
  for my $node ($dom->findnodes($xpath)) {
    return($node->getValue());
  }
  return "";
} # close sub

sub getVal {
  my ($node, $key) = @_;
  # if ($node != undef) {
  if ( defined ($node) ) {
    if (defined($node->getElementsByTagName($key))) {
      if (defined($node->getElementsByTagName($key)->item(0))) {
        if (defined($node->getElementsByTagName($key)->item(0)->getFirstChild)) {
          if (defined($node->getElementsByTagName($key)->item(0)->getFirstChild->getNodeValue)) {
           return($node->getElementsByTagName($key)->item(0)->getFirstChild->getNodeValue);
          }
        }
      }
    }
  }
  return(undef);
} # close sub

sub download {
    my ( $url, $out, ) = @_;
    print STDERR "Downloading $url with wget\n";
    my $r = system( "wget -q -O $out $url" );
    if ( $r ) {
        $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
        print STDERR "wget failed, now downloading using lwp-download\n";
        $r = system( "lwp-download $url $out" );
        if ( $r ) {
	    print STDERR "ERROR DOWNLOADING: $url\n";
		log_error( "ERROR DOWNLOADING: $url  EXITING" );
	    exit(1);
        }
    }
} # close sub

sub log_error {
    my ($mesg) = @_;
    open my ($ERR), '>>', "${gnos_url}_data_freeze_2.0_error_log_" . $timestamp . '.txt' or die;
    print $ERR "$mesg\n";
    close $ERR;
    $error_log++;
} # close sub

sub checkvar {
    my ( $var, $name, $id, ) = @_;
    unless ( $var ) {
        print STDERR "The value in \$" . "$name is False; skipping $id\n";
        #print "The value in \$" . "$name is False; skipping $id\n";
        log_error( "SKIPPED ${id}_${gnos_url}.xml because \$" . "$name was False");
        return 0;
    } # close unless test
    return 1;
} # close sub


__END__

Here is the dumped data structure with my new modification

$sample_info->{'CLLE-ES'}{'030'}{'types'}{'Tumour'}

$sample_info = \{
    'CLLE-ES' => { PROJECT
      '030' => { DONOR

        types => {
          Tumour => [
            '030-0066-01TD'
          ],
          Normal => [
            '030-0067-01ND'
          ]
        },

        specimens => {

          '030-0067-01ND' => { SPECIMEN
            '030-0067-01ND' => { SAMPLE
              use_control => 'N/A',
              sample_uuid => '9d326842-318e-4594-a225-b3e5d6d99385',
              analysis_url => 'https://gtrepo-bsc.annailabs.com/cghub/data/analysis/download/fc7b03bc-e110-11e3-8e67-07a5fb958afb',
              type => 'Normal',
              analysis_id => 'fc7b03bc-e110-11e3-8e67-07a5fb958afb',
              aliquot_id => '9d326842-318e-4594-a225-b3e5d6d99385'
            }
          },

          '030-0066-01TD' => { SPECIMEN
            '030-0066-01TD' => { SAMPLE
              use_control => '9d326842-318e-4594-a225-b3e5d6d99385',
              sample_uuid => '3f72f750-5666-44e7-acaf-a912d89475be',
              analysis_url => 'https://gtrepo-bsc.annailabs.com/cghub/data/analysis/download/fe6e9044-e110-11e3-8d55-0aa5fb958afb',
              type => 'Tumour',
              analysis_id => 'fe6e9044-e110-11e3-8d55-0aa5fb958afb',
              aliquot_id => '3f72f750-5666-44e7-acaf-a912d89475be'
            }
          }
        }
      },

Dang, wouldn't you know it, this is a singleton, the very first one

Now processing XML files for CLLE-ES

$sample_info = \{
    types => {
      Normal => [
        '002-01-1ND'
      ]
    },
    specimens => {
      '002-01-1ND' => {
        '002-01-1ND' => {
          use_control => 'N/A',
          sample_uuid => '5c182461-639b-4cda-b064-ec58df4b93eb',
          analysis_url => 'https://gtrepo-bsc.annailabs.com/cghub/data/analysis/download/33e8779c-f216-11e3-8569-f7a7fb958afb',
          type => 'Normal',
          analysis_id => '33e8779c-f216-11e3-8569-f7a7fb958afb',
          aliquot_id => '5c182461-639b-4cda-b064-ec58df4b93eb'
        }
      }
    }
  };

Running time:  0.82 minutes
514|mperry@cn4-74|bsc >

# This was the original version of this subroutine, but I changed it a bit
sub getCustomVal {
  my ($dom2, $keys) = @_;
  my @keys_arr = split /,/, $keys;
  for my $node ($dom2->findnodes('//ANALYSIS_ATTRIBUTES/ANALYSIS_ATTRIBUTE')) {
    my $i=0;
    for my $currKey ($node->findnodes('//TAG/text()')) {
      $i++;
      my $keyStr = $currKey->toString();
      foreach my $key (@keys_arr) {
        if ($keyStr eq $key) {
          my $j=0;
          for my $currVal ($node->findnodes('//VALUE/text()')) {
            $j++;   
            if ($j==$i) { 
              return($currVal->toString());
            }
          } 
        }
      }
    }
  }
  return("");
} # close sub

