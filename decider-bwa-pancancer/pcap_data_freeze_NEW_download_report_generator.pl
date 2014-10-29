#!/usr/bin/perl
#
# File: pcap_data_freeze_NEW_download_report_generator.pl
# based on, and forked from my previous script named: pcap_data_freeze_download_report_generator.pl
# This was forked on 2014-10-22
# 
# CONCEPT: For the first ICGC PanCancer Data freeze (which we ended up calling Data Freeze 
# Train 1.0) the key goal was to upload and align as many things as possible. Note that this
# was different for the first stage of Data Freeze Train 2.0 where the goal was upload as
# many unaligned bam files by a certain time.  To create accurate counts and tables of the 
# content from all of the GNOS repositories, I created a new, different, script named 
# pcap_data_freeze_2.0_NEW_report_generator.pl.  Its goal was NOT to generate a list of 
# downloadable bam files, but instead was to count who was ready to go (and paired, and stuff).
#
# Fast forward to today, now that over half of the alignments are done folks want to know
# how to get their hands on everything for downloading.  Therefore I am going update this
# script to that it meets the current code in my other scripts (error-checking and such).
#
# Last Modified: 2014-10-24, Status: in development

use strict;
use XML::DOM;
use Data::Dumper;
use JSON qw( decode_json );
use Getopt::Long;
use XML::LibXML;
use Cwd;
use Carp;

# globally overriding calls to die, and sending them to Carp

# as shown by brian d foy on page 50 in Mastering Perl

$SIG{__DIE__} = sub { &Carp::confess };

####################
# GLOBAL VARIABLES #
###################

my $error_log = 0;
my $skip_down = 0;
my $gnos_url = q{};
my $xml_file = undef;
my $uri_list = undef;

my @repos = qw( bsc cghub dkfz ebi etri osdc_icgc osdc_tcga riken );

my %urls = ( bsc        => "https://gtrepo-bsc.annailabs.com",
             cghub      => "https://cghub.ucsc.edu",
             dkfz       => "https://gtrepo-dkfz.annailabs.com",
             ebi        => "https://gtrepo-ebi.annailabs.com",
             etri       => "https://gtrepo-etri.annailabs.com",
             osdc_icgc  => "https://gtrepo-osdc-icgc.annailabs.com",
             osdc_tcga  => "https://gtrepo-osdc-tcga.annailabs.com",
             riken      => "https://gtrepo-riken.annailabs.com",
);

# a hash only used to store the analysis_ids of
# alignments
my %analysis_ids = ();
my %sample_uuids = ();
my %aliquot_ids = ();
my %list_of_t_aliq_ids = ();
my %list_of_n_aliq_ids = ();
my %aligned_aliquot_ids = (); # a hash to hold the aliquot_ids of uniformly aligned bam files
my %list_of_n_aliq_ids_from_use_cntls = ();
my %use_cntls_of = ();
my %multiple_aligned_bams = ();
my %aligned_bams = ();
my %bams_seen = ();
my %problems = ();
my %qc_p = ();
my %qc_metrics = ();
my $unpaired_specimens = {};
my $paired_specimens = {};
my $counter = 0;

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
                    'DLBC-US' => "Lymphoid Neoplasm Diffuse Large B-cell Lymphoma - TCGA, US",
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
                    'LUSC-US' => "Lung Squamous Cell Carcinoma - TCGA, US",
                    'MALY-DE' => "Malignant Lymphoma",
                    'OV-AU'   => "Ovarian Cancer - Serous cystadenocarcinoma",
                    'OV-US'   => "Ovarian Serous Cystadenocarcinoma - TCGA, US",
                    'ORCA-IN' => "Oral Cancer - Gingivobuccal",
                    'PACA-AU' => "Pancreatic Cancer - Ductal adenocarcinoma",
                    'PACA-CA' => "Pancreatic Cancer - Ductal adenocarcinoma - CA",
                    'PAEN-AU' => "Pancreatic Cancer - Endocrine neoplasms",
                    'PBCA-DE' => "Pediatric Brain Tumors",
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
my @now = localtime();
# rearrange the following to suit your stamping needs.
# it currently generates YYYYMMDDhhmmss
my $timestamp = sprintf("%04d_%02d_%02d_%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1],);

# READ INFO FROM GNOS
my $sample_info = read_sample_info();

# STEP 2. MAP SAMPLES
# Process the data structure that has been passed in and print out
# a table showing the donors, specimens, samples, number of bam files, alignment
# status, etc.
map_samples();

# STEP 3. QC
# Starting with Data Freeze Train 2.0 all of the uniform alignments will have an XML element
# containing a JSON document with Keiran's QC stats, so I am collecting those and want to print them out 
# to a separate file. %qc_metrics is a data structure where I am storing the QC Stats
# process_qc is a subroutine that will process all of the QC information stored in the entire
# %qc_metrics hash:
process_qc() if %qc_metrics;

foreach my $bam ( sort keys %bams_seen ) {
    if ( $bams_seen{$bam} > 1 ) {
        log_error( "Found multiple donors using this aligned bam: $bam" ); 
    }
} # close foreach loop

# review to see if any alignments have the same
# aliquot_id--this could happen by accident if the transfer
# or upload from SeqWare was initiated multiple times (or if the
# uniform alignment was initiated multiple times)
# This is 'BAD' because the qc_metrics calculations use the aliquot_id
# as the primary key for the data structure, and in one case
# all of the qc numbers were doubled (e.g., the average coverage).
# This information (that there are multiple analysis ids for 
# one aliquot ID will get printed out to the error log

foreach my $id ( sort keys %aligned_aliquot_ids ) {
    # this data structure is a hash of arrays
    my $upload_count = scalar(@{$aligned_aliquot_ids{$id}});
    if ( $upload_count > 1 ) {
        log_error( "Found $upload_count alignment analysis_ids using this aliquot_id: $id" ); 
    }
} # close foreach loop

# if any errors were detected during the run, notify the user
if ( $error_log ) {
    print STDERR "WARNING: Logged $error_log errors in ${gnos_url}_data_freeze_download_report_generator_error_log.txt stamped with $timestamp\n";
}
else {
    print STDERR "NO ERRORS FOUND: Apparently no errors were detected while processing pcap_data_freeze_download_report_generator.pl for $gnos_url\n";
}

END {
    no integer;
    printf( STDERR "Running time: %5.2f minutes\n",((time - $^T) / 60));
} # close END block

###############
# SUBROUTINES #
###############

sub map_samples {
    foreach my $project (sort keys %{$sample_info}) {
        if ( $project ) {
            print STDERR "Now processing XML files for $project\n";
        }
        # Parse the data structure built from all of the XML files, and parse them out
        # into three categories--and three new data structures
        foreach my $donor ( keys %{$sample_info->{$project}} ) {
            # at a minimum, each donor should have two specimens (or types)
            # a Normal specimen, or type, and a Tumour specimen, or type
            # Based on the snapshot of live analysis objects in this
            # GNOS repo, on this day, calculate which donors have matched
            # pairs of Tumour/Normal specimens
            my %types = ();
            my @specimens = keys %{$sample_info->{$project}{$donor}};
            my $num_of_specimens = scalar( @specimens );
            foreach my $specimen ( @specimens ) {
                foreach my $sample ( keys %{$sample_info->{$project}{$donor}{$specimen}} ) {
                    foreach my $alignment ( keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}} ) {
                        my $type = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{type};
                        # so we have created a hash named %types and it can have up to two hash keys
                        # Normal and Tumour.  The Submitted specimen IDs get captured into an array
                        # stored as the value of the respective hash keys.
                        push @{$types{$type}}, $specimen unless ( grep {/$specimen/} @{$types{$type}} );
		    } # close alignment foreach loop
		} # close sample foreach loop
	    } # close specimen foreach loop
            my $unpaired = 0;
            my $paired = 0;

            # How many keys are in the %types hash?
            if ( scalar keys %types == 1 ) {
                $unpaired = 1;
	    }
            else {
                # two hash keys = two sample types, 'Normal' & 'Tumour'
                $paired = 1;
	    }

            foreach my $type ( keys %types ) {
                if ( $type eq 'Normal' ) {
                    # find out if there are multiple Normal specimens
                    # and then skip this, because that is an error
                    if ( scalar( @{$types{$type}} > 1 ) ) {
                        log_error( "Found more than two Normal specimens for this donor: $donor    SKIPPING" );
                        next;
                    } 
		}
	    } # close outer foreach loop

            if ( $num_of_specimens == 1 ) {
                # This cannot be paired if there is only a single specimen
                # but that could be either a Tumour or a Normal
                $unpaired_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};
	    }
            elsif ( $num_of_specimens == 2 ) {
                # This might be paired because there are exactly 2 specimens for this donor
                # but it could also be 2 Normals (!?!) or 2 Tumours, so strictly speaking, NOT paired
                if ( $unpaired ) {
                    $unpaired_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};
		} 
                else { 
                    $paired_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};      
	        }
            } 
	    elsif ( $num_of_specimens > 2 ) {
                # This has more than 2 specimens, The could be duplicated samples, but
                # they could also be 1 normal with multiple tumours, or multiple tumours
                # without any normals
                if ( $unpaired ) {
                    $unpaired_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};
		} 
                else { 
                    $paired_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};      
	        }
	    }
            else {
                # No specimens, skip it
                log_error( "No specimens found for Project: $project Donor: $donor    SKIPPING" );
                next;
	    }
	} # close foreach $donor
    } # close foreach project

    # At this point all of the data parsed from the xml files should be allocated into
    # one of these two hash references (unless the specimen field was blank
    # Test each hash reference to see if it contains any data, if it does
    # then use the process_specimens subroutine to extract that data into a table
    # and print out each table into individual files:
    if ( keys %{$unpaired_specimens} ) {
        open my $FH1, '>', "${gnos_url}_pcap_download_report_for_unpaired_specimen_alignments_" . $timestamp . '.tsv' or die;
        process_specimens( $unpaired_specimens, $FH1, 0, );
        close $FH1;
    }

    if ( keys %{$paired_specimens} ) {
        open my $FH2, '>', "${gnos_url}_pcap_download_report_for_paired_alignments_" . $timestamp . '.tsv' or die;
        process_specimens( $paired_specimens, $FH2, 1, );
        close $FH2;
    }
} # close sub

sub process_specimens {
    my ( $sample_info, $FH, $paired, )  =  @_;
    my $endpoint = $urls{$gnos_url};
    if ( $paired ) {
        print $FH "Study\tProject Code\tDonor ID\tNormal Specimen/Sample ID\tNormal Sample/Aliquot ID\tNormal/Tumour designation\tNormal Analyzed Sample/Aliquot GUUID\tNormal GNOS endpoint\tNormal Analysis ID\tNormal bam file\tTumour Specimen/Sample ID\tTumour Sample/Aliquot ID\tNormal/Tumour designation\tTumour Analyzed Sample/Aliquot GUUID\tTumour GNOS endpoint\tTumour Analysis ID\tTumour bam file\n";
        foreach my $project (sort keys %{$sample_info}) {
            my $study = $study_names{$project};
            $study = "NO STUDY FOUND" unless $study;     
            foreach my $donor ( keys %{$sample_info->{$project}} ) {
                # if it is paired then this particular donor is going to have at least 2 specimens,
                # and possibly more than two
                # find the 'Normal' and extract its data fields
                my $normal = undef;
                my $tumour = undef;
                my @tumours = ();
                foreach my $specimen (keys %{$sample_info->{$project}{$donor}}) {
                    # we need to establish if this is the 'Normal' or the 'Tumour' because
                    # each one will have have different actions
                    foreach my $sample ( keys %{$sample_info->{$project}{$donor}{$specimen}} ) {
                        foreach my $alignment ( keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}} ) {
                            my $type = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{type};
                            if ( $type eq 'Normal') {
                                $normal = extract_normal( $specimen, $donor, $endpoint, );
			    }
                            else {
                                $tumour = extract_tumour( $specimen, $endpoint, );
                                push @tumours, $tumour;
			    }
			}
		    }
                    foreach my $tumour ( @tumours ) {
                        print $FH "$study\t$project\t$donor\tspecimen\t", $normal, $tumour, "\n";
                    }
		} # close third foreach loop
	    } # close second foreach loop
	} # close outer foreach loop
    }
    else {
        print $FH "Study\tProject Code\tDonor ID\tSpecimen/Sample ID\tSample/Aliquot ID\tNormal/Tumour designation\tAnalyzed Sample/Aliquot GUUID\tGNOS endpoint\tAnalysis ID\tbam file\n";
        foreach my $project (sort keys %{$sample_info}) {
            my $study = $study_names{$project};
            $study = "NO STUDY FOUND" unless $study;     
            foreach my $donor ( keys %{$sample_info->{$project}} ) {
                foreach my $specimen (keys %{$sample_info->{$project}{$donor}}) {
                    foreach my $sample ( keys %{$sample_info->{$project}{$donor}{$specimen}} ) {
                        foreach my $alignment ( keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}} ) {
                            my $type = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{type};
                            my $aliquot_id = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{aliquot_id};
                            foreach my $bam (keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}}) {
                                $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{bams_count}++;
                            }
                            my $analysis_id = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{analysis_id};
                            my $aligned_bam = q{};
                            my $num_bam_files = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{bams_count};
                            # Test and see if there is only a single bam file
              	            if ( $num_bam_files == 1 ) {
                                ($aligned_bam) = keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}};
                                $bams_seen{$aligned_bam}++;
			    }
    			    elsif ( $num_bam_files > 1 ) {
                                ($aligned_bam) = sort keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}};     
                                my $bam;
                                foreach (sort keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}} ) {
                                    $bam .= "$_ ";
                                }     
                                log_error( "Found $num_bam_files bam files for $donor $specimen $sample $bam" );
                                $bams_seen{$aligned_bam}++;
                            }
                            else {
                                log_error( "Could not find any aligned bam files for donor: $donor" );
                                $aligned_bam = 'NONE';
			    }
                            print $FH "$study\t$project\t$donor\t$specimen\t$sample\t$type\t$aliquot_id\t$endpoint\t$analysis_id\t$aligned_bam";
		    } # close foreach my alignment
		} # close foreach my sample
	    } # close foreach my specimen
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
        $doc = $parser->parsefile("$xml_file");
        my $nodes = $doc->getElementsByTagName ("Result");
        my $n = $nodes->getLength;

        # iterate over the Result XML files that were downloaded into the 
        # xml/ directory  
        for ( my $i = 0; $i < $n; $i++ ) {
            my $node = $nodes->item ($i);
            my $aurl = getVal($node, "analysis_full_uri"); 
            if ( $aurl =~ /^(.*)\/([^\/]+)$/ ) {
                $aurl = $1."/".lc($2);
            } 
            push @uris, $aurl;
        }   
        $doc->dispose;
    }
    elsif ( $uri_list ) {
        open my $URIS, '<', $uri_list or die "Could not open $uri_list for reading!";
        @uris = <$URIS>;
        chomp( @uris );
        close $URIS;
    }
    print STDERR "Entering foreach my \$uri loop\n";
    foreach my $uri ( @uris ) {
        $counter++;
        my ( $id ) = $uri =~ m/analysisFull\/([\w-]+)$/;
#        print "File number $counter: $id\n";
        print STDERR ">> Processing $id, checking for files\n";
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

        # test to see if the download and everything worked
        if ( -e "xml/${id}_${gnos_url}.xml" ) {
            # test for file contents to avoid XML parsing errors that kill script
            if ( -z "xml/${id}_${gnos_url}.xml" ) {
                print STDERR "This XML file has zero size (i.e., is empty): ${id}_${gnos_url}.xml    SKIPPING\n\n";
                log_error( "SKIPPING xml file is empty and has zero size: ${id}_${gnos_url}.xml" );
                next;
	    }
        
            # create an XML::DOM object:
            $adoc = $parser->parsefile ("xml/${id}_${gnos_url}.xml");
            # create ANOTHER XML::DOM object, using a different Perl library
            # I was always creating an additional new object
            # in the previous code, so now I am trying to do it
            # the same as the other parser, and keep reusing it 
            # on each iteration
            $adoc2 = $parser2->parse_file("xml/${id}_${gnos_url}.xml");
	}
        else {
            print STDERR "Could not find this xml file: ${id}_${gnos_url}.xml    SKIPPING\n\n";
            log_error( "SKIPPING Could not find xml file: ${id}_${gnos_url}.xml" );
            next;
	}

        # 2014-10-15 N.B. This script ignores any files that do not contained
        # aligned bams, and so we would expect a single analysis_id that
        # would uniquely identify this one XML file that is currently being
        # parsed:

        my $alignment = getVal($adoc, "refassem_short_name");
        next unless checkvar( $alignment, 'refassem_short_name', $id, );       
        if ( $alignment eq 'unaligned' ) {
            # print "        Skipping file number $counter: unaligned\n";
            # this script keeps dying when parsing EBI without any explanation
            # could I be leaving a lot of objects around from the unaligned?
            $adoc->dispose;
            next;
	}
        # at thispoint they are all aligned
        # my $aln_status = 0;
        # if ( $alignment ne 'unaligned' ) {
        #    $aln_status = 1;
        # }
        my $project = getCustomVal($adoc2, 'dcc_project_code');
        next unless checkvar( $project, 'project', $id, );
        my $donor_id = getCustomVal($adoc2, 'submitter_donor_id');
        next unless checkvar( $donor_id, 'donor_id', $id, );
        my $specimen_id = getCustomVal($adoc2, 'submitter_specimen_id');
        next unless checkvar( $specimen_id, 'specimen_id', $id, );
        my $sample_id = getCustomVal($adoc2, 'submitter_sample_id');
        next unless checkvar( $sample_id, 'sample_id', $id, );
        my $analysis_id = getVal($adoc, 'analysis_id');
        my $mod_time = getVal($adoc, 'last_modified');
        my $analysisDataURI = getVal($adoc, 'analysis_data_uri');
        my $aliquot_id = getVal($adoc, 'aliquot_id');
        next unless checkvar( $aliquot_id, 'aliquot_id', $id, );
        my $use_control = getCustomVal($adoc2, "use_cntl");
        next unless checkvar( $use_control, 'use_control', $id, );
        # make sure that you are comparing lc vs lc (but not for the Normal samples)
        $use_control = lc($use_control) unless $use_control =~ m/N\/A/;
        my $dcc_specimen_type = getCustomVal($adoc2, 'dcc_specimen_type');
        next unless checkvar( $dcc_specimen_type, 'dcc_specimen_type', $id, );
        my $study = getVal($adoc, 'study');

        # Apparently CGHub doesn't have this element/field
        # my $submitterAliquotId = getCustomVal($adoc2, 'submitter_aliquot_id');

        # Test if this XML file is for a TCGA dataset
        if ( $study eq 'PAWG' ) {
            # TCGA datasets use that analysis_id instead of the aliquot_id
            # to identify the correct paired Normal dataset
            $aliquot_id = $analysis_id;
        }
        else {
            $aliquot_id = getVal($adoc, 'aliquot_id');
        }

        my $description = getVal($adoc, 'DESCRIPTION');
        next unless checkvar( $description, 'DESCRIPTION', $id, );       
        my $qc_json = 0;
        my $dupl_json = 0;

        # recall: we are only processing alignedments, so we no longer need to test this
        # if ( $aln_status) {
        # don't bother tabulating alignments containing unmapped reads
        next if $description =~ m/unmapped reads extracted/;
        # only tabulate alignments for Data Freeeze 2.0
        next unless $description =~ m/Workflow version 2\.6\.\d/;
        push @{$aligned_aliquot_ids{$aliquot_id}}, $analysis_id;
        $qc_json = getCustomVal($adoc2, "qc_metrics");
        $dupl_json = getCustomVal($adoc2, "markduplicates_metrics");
	# }
        # Apparently CGHub doesn't have this field/element?
        # my $total_lanes = getCustomVal($adoc2, "total_lanes");
        my $sample_uuid = getXPathAttr($adoc2, "refname", "//ANALYSIS_SET/ANALYSIS/TARGETS/TARGET/\@refname");


        # in the data structure each Analysis Set is sorted by it's ICGC DCC project code, then the combination of
        # donor, specimen, and sample that should be unique identifiers
        # For aligned samples there should be a single modification date

        push @{ $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{date} }, $mod_time; 
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{analysis_url} = $analysisDataURI; 
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{use_control} = $use_control; 
        #$d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{total_lanes} = $total_lanes;
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{sample_uuid} = $sample_uuid;
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{analysis_id} = $analysis_id;
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{aliquot_id} = $aliquot_id;

        my $type;
        # First check to see if there is a value in use_cntl
        # then check to see if it is N/A.  If it is N/A then this is a Normal sample
        if ( $use_control && $use_control ne 'N/A' ) {
            # if it passes the test then it must be a 'Tumour', so we assign it a 'type'
            # in this case the 'type' = 'Tumour'
            $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{type} = 'Tumour';
            $type = 'Tumour';

            # Now lets check to see if this type matches the contents of the dcc_specimen_type
            if ( $dcc_specimen_type =~ m/Normal/ ) {
                log_error( "MISMATCH dcc_specimen type in ${id}_${gnos_url}.xml OVERRIDING from Tumour to Normal" );            
                $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{type} = 'Normal';
                $type = 'Normal';
                $norm_aliquot_ids{$aliquot_id}++; 
            }            
            else {
                # keep track of the correct use_cntl for this Tumor Sample by storing
                # this information in the %use_cntls hash, where the hash key is the 
                # aliquot_id for this sample, and the hash value is the use_cntl for
                # this sample, extracted from the XML files
                $use_cntls{$aliquot_id} = $use_control;
                # add the aliquot_id to a list of the all the Tumour Aliquot IDs
                $tum_aliquot_ids{$aliquot_id}++;
                # add the aliquot_id specified as the Normal control to a list of all
                # the Normal aliquot IDs that get exrtracted from all the XML files
                $norm_use_cntls{$use_control}++;
            }
        }
        else {
            # otherwise, this is not a Tumour, so we give it a 'type'
            # 'type' = Normal
            $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{type} = 'Normal';
            $type = 'Normal';
            # Now lets check to see if this type matches the contents of the dcc_specimen_type
            if ( $dcc_specimen_type =~ m/tumour/ ) {
                log_error( "MISMATCH dcc_specimen type in ${id}_${gnos_url}.xml OVERRIDING from Normal to Tumour" );            
                $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{type} = 'Tumour';
                $type = 'Tumour';
                $tum_aliquot_ids{$aliquot_id}++;
                $use_cntls{$aliquot_id} = $use_control;
                $norm_use_cntls{$use_control}++;
            }            
            else {
                # Add this aliquot ID to this list of all the 'Normal' 
                # aliquot ids encountered in this XML
                $norm_aliquot_ids{$aliquot_id}++;
	    }
        }

        my $files = readFiles($adoc);
        foreach my $file(keys %{$files}) {
              next if $file =~ m/\.bai/;
              $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{files}{$file}{size} = $files->{$file}{size}; 
              $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{files}{$file}{checksum} = $files->{$file}{checksum}; 
              $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{files}{$file}{localpath} = "$file"; 
              # $bams_seen{$file}{$sample_id}++;
# if this is an alignment from Data Freeze Train 2.0 then extract the qc details and print them out
            if ( $qc_json ) {
                my $param = {
                    json => $qc_json,
                    dupl => $dupl_json,
                    bam => $file,
                    size => $files->{$file}{size},
                    project => $project,
                    donor => $donor_id,
                    specimen => $specimen_id,
                    sample => $sample_id,
                    analysis_id => $analysis_id, # analysis_id for this uniformly aligned bam file
                    aliquot_id => $aliquot_id, # aliquot_id for this uniformly aligned bam file
                    type => $type,
                  };
                extract_qc( $param );
	    }
        } # close foreach my $file
        $adoc->dispose;
        # print "    Finished parsing Record number $counter: $id\n";
    } # close foreach my $uri loop
    return($d);
} # close sub

sub readFiles {
    my ($d) = @_;
    my $ret = {};
    my $nodes = $d->getElementsByTagName ("file");
    my $n = $nodes->getLength;
    for ( my $i = 0; $i < $n; $i++ ) {
        my $node = $nodes->item ($i);
        my $currFile = getVal($node, 'filename');
	my $size = getVal($node, 'filesize');
	my $check = getVal($node, 'checksum');
        $ret->{$currFile}{size} = $size;
        $ret->{$currFile}{checksum} = $check;
    }
  return($ret);
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
  if ($node != undef) {
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
  my ($url, $out) = @_;

  my $r = system("wget -q -O $out $url");
  if ($r) {
	  $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
    $r = system("lwp-download $url $out");
    if ($r) {
	    print "ERROR DOWNLOADING: $url\n";
	    exit(1);
    }
  }
} # close sub


sub extract_qc {
    # this is a hashref coming in
    my ( $param ) = @_;
    # convert the json document into a a perl 
    # data structure
    my $decoded = decode_json($param->{json});
    my $analysis_id = $param->{analysis_id};
    # Okay, at this first step, let's just grab the data structures
    # and store them all together.  We will process them later
    # each read group (@RG) in the uniformly aligned bam
    # file has its own hash ref
    my @qc = @{ $decoded->{qc_metrics} };
    foreach my $qc_hash ( @qc ) {
        # the hash keys for the qc_metrics array are the
        # analysis_ids for each uniformly aligned bam file
        push @{$qc_metrics{$analysis_id}}, $qc_hash->{metrics};
    } # close outer foreach loop
    # this is a second cute little hash where
    # I am also storing the parameters that I passed
    # in so that I can use them later.
    $qc_p{$analysis_id} = $param;
} # close sub

sub process_qc {
    # So my idea here is to iterate over the qc_metrics data structure we built and perform the necessary calculations
    # Then addin the relevant values from the qc_param
    # and then print that out to a separate file
    open my ($QC), '>', "$gnos_url" . '_pcap_download_qc_metrics_report_' . "$timestamp" . '.tsv' or die "Could not open file to write qc report";
    my @fields = ( 'DCC Project Code', 'Donor ID', 'Specimen ID', 'Sample ID', 'Type', 'analysis_id', 'aliquot_id', 'bam file name', 'bam file size', '#_total_bases', '#_total_mapped_bases', '#_total_reads', 'average coverage', '%_mapped_bases', '%_mapped_reads', '%_mapped_reads_properly_paired', '%_unmapped_reads', '%_duplicated_reads', '%_GC_r1_and_r2', '%_divergent_bases', );
    print $QC join( "\t", @fields, ), "\n";
    my %multiple_alignments = ();
    foreach my $analysis_id ( sort keys %qc_metrics ) {
        # test to see if we already analyzed a different analysis_id for this
        # same aliquot_id
        if ( $multiple_alignments{$qc_p{$analysis_id}->{aliquot_id}} ) {
            next;
	}
        # keep a running track of each analysis_id and aliquot_id
        $multiple_alignments{$qc_p{$analysis_id}->{aliquot_id}}++;
        my $total_bases = 0;
        my $total_reads = 0;
        my $total_mapped_bases = 0;
        my $total_mapped_reads = 0;
        my $total_divergent_bases = 0;
        my $total_mapped_reads_prop_pair = 0;
        my $total_dupl_reads = 0;    
        my $total_gc_r1_and_r2 = 0;
        foreach my $qc ( @{$qc_metrics{$analysis_id}} ) {
            $total_bases += ( $qc->{'#_total_reads_r1'} * $qc->{read_length_r1} ) + ( $qc->{'#_total_reads_r2'} * $qc->{read_length_r2} );
            $total_mapped_bases += ( $qc->{'#_mapped_reads_r1'} * $qc->{read_length_r1} ) + ( $qc->{'#_mapped_reads_r2'} * $qc->{read_length_r2} );
            $total_reads += $qc->{'#_total_reads'};
            $total_mapped_reads += $qc->{'#_mapped_reads'};
            $total_divergent_bases += $qc->{'#_divergent_bases'};
            $total_mapped_reads_prop_pair += $qc->{'#_mapped_reads_properly_paired'};
            $total_dupl_reads += $qc->{'#_duplicate_reads'};
            $total_gc_r1_and_r2 += $qc->{'#_gc_bases_r1'} + $qc->{'#_gc_bases_r2'};
        } # close 2nd foreach loop
        my $avg_covg = $total_mapped_bases / 3000000000; 
        my $percent_mapped_bases = ($total_mapped_bases / $total_bases) * 100;
        my $percent_mapped_reads = ($total_mapped_reads / $total_reads) * 100;
        my $percent_mapped_reads_prop_pair = ($total_mapped_reads_prop_pair / $total_reads) * 100;
        my $total_unmapped_r1_and_r2 = $total_reads - $total_mapped_reads;
        my $percent_unmapped = ($total_unmapped_r1_and_r2 / $total_reads) * 100;
        my $percent_dupl_reads = ($total_dupl_reads / $total_reads) * 100;
        my $percent_GC_r1_and_r2 = ($total_gc_r1_and_r2 / $total_bases) * 100; 
        my $percent_divergent_bases = ($total_divergent_bases / $total_bases) * 100;
        print $QC join "\t", ( $qc_p{$analysis_id}->{project},
                               $qc_p{$analysis_id}->{donor},         
                               $qc_p{$analysis_id}->{specimen},
                               $qc_p{$analysis_id}->{sample},
                               $qc_p{$analysis_id}->{type},
                               $analysis_id,
                               $qc_p{$analysis_id}->{aliquot_id},
                               $qc_p{$analysis_id}->{bam},
                               $qc_p{$analysis_id}->{size},                                
                               $total_bases,
                               $total_mapped_bases,
                               $total_reads,
                               $avg_covg,
                               $percent_mapped_bases,
                               $percent_mapped_reads,
                               $percent_mapped_reads_prop_pair,
                               $percent_unmapped,
                               $percent_dupl_reads,
                               $percent_GC_r1_and_r2,
                               $percent_divergent_bases,
                              ), "\n";

    } # close 1st foreach loop
    close $QC;
} # close sub

sub log_error {
    my ($mesg) = @_;
    open my ($ERR), '>>', "${gnos_url}_data_freeze_download_error_log_" . $timestamp . '.txt' or die;
    print $ERR "$mesg\n";
    close $ERR;
    $error_log++;
} # close sub

sub checkvar {
    my ( $var, $name, $id, ) = @_;
    unless ( $var ) {
        print STDERR "The value in \$" . "$name is False; skipping $id\n";
        log_error( "SKIPPED ${id}_${gnos_url}.xml because \$" . "$name was False");
        return 0;
    } # close unless test
    return 1;
} # close sub

sub extract_normal {
    my $var = q{};
    my ( $specimen, $donor, $endpoint, ) = @_;
    foreach my $sample ( keys %{$donor->{$specimen}} ) {
        foreach my $alignment ( keys %{$donor->{$specimen}{$sample}} ) {
            my $type = $donor->{$donor}{$specimen}{$sample}{$alignment}{type};
            my $aliquot_id = $donor->{$specimen}{$sample}{$alignment}{aliquot_id};
            my $sample_uuid = $donor->{$specimen}{$sample}{$alignment}{sample_uuid};
            foreach my $bam (keys %{$donor->{$specimen}{$sample}{$alignment}{
                $donor->{$specimen}{$sample}{$alignment}{bams_count}++;
            }
            my $analysis_id = $donor->{$specimen}{$sample}{$alignment}{analysis_id};
            my $aligned_bam = q{};
            my $num_bam_files = $donor->{$specimen}{$sample}{$alignment}{bams_count};
            # Test and see if there is only a single bam file
            if ( $num_bam_files == 1 ) {
                ($aligned_bam) = keys %{$donor->{$specimen}{$sample}{$alignment}{files}};
                $bams_seen{$aligned_bam}++;
	    }
    	    elsif ( $num_bam_files > 1 ) {
                ($aligned_bam) = sort keys %{$donor->{$specimen}{$sample}{$alignment}{files}};     
                my $bam;
                foreach (sort keys %{$donor->{$specimen}{$sample}{$alignment}{files}} ) {
                    $bam .= "$_ ";
                }     
                log_error( "Found $num_bam_files bam files for $donor $specimen $sample $bam" );
                $bams_seen{$aligned_bam}++;
            }
            else {
                log_error( "Could not find any aligned bam files for donor: $donor" );
                $aligned_bam = 'NONE';
	    }
        }
    }
    $var = "$sample\t$aliquot_id\t$type\t$sample_uuid\t$endpoint\t$analysis_id\t$aligned_bam\t"

        print $FH "Study\tProject Code\tDonor ID\tNormal Specimen/Sample ID\tNormal Sample/Aliquot ID\tNormal/Tumour designation\tNormal Analyzed Sample/Aliquot GUUID\tNormal GNOS endpoint\tNormal Analysis ID\tNormal bam file\tTumour Specimen/Sample ID\tTumour Sample/Aliquot ID\tNormal/Tumour designation\tTumour Analyzed Sample/Aliquot GUUID\tTumour GNOS endpoint\tTumour Analysis ID\tTumour bam file\n";

    return $var;
} # close sub

sub extract_tumour {
    my ( $specimen, $donor, ) = @_;
    foreach my $sample ( keys %{$donor->{$specimen}} ) {
        foreach my $alignment ( keys %{$donor->{$specimen}{$sample}} ) {
            my $type = $donor->{$donor}{$specimen}{$sample}{$alignment}{type};
            my $aliquot_id = $donor->{$specimen}{$sample}{$alignment}{aliquot_id};
            foreach my $bam (keys %{$donor->{$specimen}{$sample}{$alignment}{
                $donor->{$specimen}{$sample}{$alignment}{bams_count}++;
            }
            my $analysis_id = $donor->{$specimen}{$sample}{$alignment}{analysis_id};
            my $aligned_bam = q{};
            my $num_bam_files = $donor->{$specimen}{$sample}{$alignment}{bams_count};
            # Test and see if there is only a single bam file
            if ( $num_bam_files == 1 ) {
                ($aligned_bam) = keys %{$donor->{$specimen}{$sample}{$alignment}{files}};
                $bams_seen{$aligned_bam}++;
	    }
    	    elsif ( $num_bam_files > 1 ) {
                ($aligned_bam) = sort keys %{$donor->{$specimen}{$sample}{$alignment}{files}};     
                my $bam;
                foreach (sort keys %{$donor->{$specimen}{$sample}{$alignment}{files}} ) {
                    $bam .= "$_ ";
                }     
                log_error( "Found $num_bam_files bam files for $donor $specimen $sample $bam" );
                $bams_seen{$aligned_bam}++;
            }
            else {
                log_error( "Could not find any aligned bam files for donor: $donor" );
                $aligned_bam = 'NONE';
	    }


    return $var;
} # close sub

__END__

