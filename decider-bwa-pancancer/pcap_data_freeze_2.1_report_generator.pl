#!/usr/bin/perl
#
# File: pcap_data_freeze_2.1_report_generator.pl
# 
# based on, and forked from my previous script named: gnos_report_generator__2014_05_01.pl
#
# Last Modified: 2014-07-16, Status: basically working

use strict;
use XML::DOM;
use Data::Dumper;
use JSON;
use Getopt::Long;
use XML::LibXML;
use Cwd;

#############
# VARIABLES #
#############
my $error_log = 0;
my $skip_down = 0;
my $gnos_url = q{};
my $specific_sample;
my $ignore_lane_cnt = 0;
my $upload_results = 0;
my $xml_file = undef;
my $uri_list = undef;

my @repos = qw( bsc cghub dkfz ebi etri osdc );

my %urls = ( bsc   => "https://gtrepo-bsc.annailabs.com",
             cghub => "https://cghub.ucsc.edu",
             dkfz  => "https://gtrepo-dkfz.annailabs.com",
             ebi   => "https://gtrepo-ebi.annailabs.com",
             etri  => "https://gtrepo-etri.annailabs.com",
             osdc  => "https://gtrepo-osdc.annailabs.com",
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
my $two_specimens = {};
my $many_specimens = {};

my %study_names = ( 'BLCA-US' => "Bladder Urothelial Cancer - TGCA, US",
                    'BOCA-UK' => "Bone Cancer - Osteosarcoma / chondrosarcoma / rare subtypes",
                    'BRCA-EU' => "Breast Cancer - ER+ve, HER2-ve",
                    'BRCA-US' => "Breast Cancer - TCGA, US",
                    'BRCA-UK' => "Breast Cancer - Triple Negative/lobular/other",
                    'BTCA-SG' => "Biliary tract cancer - Gall bladder cancer / Cholangiocarcinoma",
                    'CESC-US' => "Cervical Squamous Cell Carcinoma - TCGA, US",
                    'CLLE-ES' => "Chronic Lymphocytic Leukemia - CLL with mutated and unmutated IgVH",
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
                    'ORCA-IN' => "Oral Cancer – Gingivobuccal",
                    'OV-AU'   => "Ovarian Cancer - Serous cystadenocarcinoma",
                    'OV-US'   => "Ovarian Serous Cystadenocarcinoma - TCGA, US",
                    'PACA-AU' => "Pancreatic Cancer - Ductal adenocarcinoma",
                    'PACA-CA' => "Pancreatic Cancer - Ductal adenocarcinoma - CA",
                    'PAEN-AU' => "Pancreatic Cancer - Endocrine neoplasms",
                    'PBCA-DE' => "Pediatric Brain Tumors",
                    'PRAD-CA' => "Prostate Cancer – Adenocarcinoma; Prostate Adenocarcinoma",
                    'PRAD-US' => "Prostate Adenocarcinoma - TCGA, US",
                    'READ-US' => "Rectum Adenocarcinoma - TCGA, US",
                    'SARC-US' => "Sarcoma - TCGA, US",
                    'SKCM-US' => "Skin Cutaneous melanoma - TCGA, US",
                    'STAD-US' => "Gastric Adenocarcinoma - TCGA, US",
                    'THCA-US' => "Head and Neck Thyroid Carcinoma - TCGA, US",
                    'UCEC-US' => "Uterine Corpus Endometrial Carcinoma- TCGA, US",
);

# MDP: these are the two that you may really want to use:
# --gnos-url (one of the six choices above)
# --skip-meta-download 
#   print "\t--gnos-url           a URL for a GNOS server, e.g. https://gtrepo-ebi.annailabs.com\n";
#   print "\t--skip-meta-download use the previously downloaded XML from GNOS\n";

GetOptions("gnos-url=s" => \$gnos_url, "xml-file=s" => \$xml_file, "sample=s" => \$specific_sample, "ignore-lane-count" => \$ignore_lane_cnt, "skip-meta-download" => \$skip_down, "uri-list=s" => \$uri_list, );

my $usage = "USAGE: There are two ways to runs this script:\Either provide the name of an XML file on the command line:\n$0 --xml-file <data.xml> --gnos-url <repo>\n OR provide the name of a file that contains a list of GNOS repository analysis_full_uri links:\n$0 --uri-list <list.txt> --gnos-url <repo>.\n\nThe script will also generate this message if you provide both an XML file AND a list of URIs\n";

die $usage unless $xml_file or $uri_list;
die $usage if $xml_file and $uri_list;
die $usage unless $gnos_url;

##############
# MAIN STEPS #
##############
print STDERR scalar localtime, "\n\n";

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
print STDERR "WARNING: Logged $error_log errors in data_freeze_2.0_error_log.txt stamped with $timestamp\n" if $error_log;

END {
    no integer;
    printf( STDERR "Running time: %5.2f minutes\n",((time - $^T) / 60));
} # close END block

###############
# SUBROUTINES #
###############

sub map_samples {
    my $rec_no = 0;
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
            my $specimen_count = scalar( @specimens );
            foreach my $specimen ( @specimens ) {
                foreach my $sample ( keys %{$sample_info->{$project}{$donor}{$specimen}} ) {
                    foreach my $alignment ( keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}} ) {
                        my $type = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{type};
                        push @{$types{$type}}, $specimen unless ( grep {/$specimen/} @{$types{$type}} );
		    } # close alignment foreach loop
		} # close sample foreach loop
	    } # close specimen foreach loop
            my $unpaired = 0;
            my $paired = 0;
            my $many_normals = 0;
            my $many_tumours = 0;
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
                elsif ( $type eq 'Tumour' ) {
                    if ( scalar( @{$types{$type}} > 1 ) ) {
                        $many_tumours = 1;
		    }
		}
	    } # close outer foreach loop

            # print "\n", Data::Dumper->new([\%types],[qw(types)])->Indent(1)->Quotekeys(0)->Dump, "\n";
            # These are exclusive tests, so test the worse case first
	    if ( $many_normals ) {
                log_error( "Found more than two Normal specimens for this donor: $donor" );
                $many_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};
	    }
            elsif ( $paired ) {
                $two_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};      
	    }
            elsif ( $unpaired ) {
                $single_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};
            } 
            else {
                # No specimens, skip it
                log_error( "No specimens found for Project: $project Donor: $donor SKIPPING" );
                next;
	    }
           
	    if ( $many_tumours ) {
                log_error( "Found more than two Tumour specimens for this donor: $donor" );
	    }

	} # close foreach $donor
    } # close foreach project

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

    if ( keys %{$two_specimens} ) {
        open my $FH2, '>', "$gnos_url" . '_paired_data_freeze_2.0_table_' . $timestamp . '.tsv' or die;
        process_specimens( $two_specimens, $FH2, );
        close $FH2;
    }

    if ( keys %{$many_specimens} ) {
        open my $FH3, '>', "$gnos_url" . '_many_specimen_alignments_excluded_' . $timestamp . '.tsv' or die;
        process_specimens( $many_specimens, $FH3, );
        close $FH3;
    }
} # close sub

sub process_specimens {
    my $sample_info = shift @_;
    my $FH = shift @_;
    my $endpoint = $urls{$gnos_url};

    print $FH "Study\tProject Code\tDonor ID\tNormal Specimen/Sample ID\tNormal Sample/Aliquot ID\tNormal Analyzed Sample/Aliquot GUUID\tNormal GNOS endpoint\tTumour Specimen/Sample ID\tTumour Sample/Aliquot ID\tTumour Analyzed Sample/Aliquot GUUID\tTumour GNOS endpoint\n";
    foreach my $project (sort keys %{$sample_info}) {
        my $study = $study_names{$project};
        $study = "NO STUDY FOUND" unless $study;     
        foreach my $donor ( keys %{$sample_info->{$project}} ) {
            print $FH "$study\t$project\t$donor\t";
            my @specimens = keys %{$sample_info->{$project}{$donor}};
            foreach my $specimen ( @specimens ) {
                my $d = {};
                my $aligns = {};
                foreach my $sample ( keys %{$sample_info->{$project}{$donor}{$specimen}} ) {
                    foreach my $alignment ( keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}} ) {
                        my $type = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{type};
                        my $aliquot_id = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{aliquot_id};
                        my $analysis_id = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{analysis_id};
     	                $aligns->{$alignment} = 1; # Why is Brian doing this?
                            # MDPQ: Whare are we reading lane counts in this script, they have all been aligned
                            # read lane counts
                            my $total_lanes = 0;
                            foreach my $lane (keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{total_lanes}}) {
                                if ($lane > $total_lanes) { 
                                    $total_lanes = $lane; 
                                }
                            } # close foreach loop
                            $d->{total_lanes_hash}{$total_lanes} = 1;
                            $d->{total_lanes} = $total_lanes;
                            foreach my $bam (keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}}) {
                                # next if $bam =~ m/bai/;
                                $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{bams_count}++;
                                $d->{bams}{$bam} = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}{$bam}{localpath};
                                $d->{local_bams}{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}{$bam}{localpath}} = 1;
                                $d->{bams_count}++;
                            }
                            # I am not sure, but I have an inkling that I don't need all of this for Data Freeze Train 2.0
                            # my $aligned_bam = q{};
                            # my $num_bam_files = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{bams_count};
                            # Test and see if there is only a single bam file
              	            # if ( $num_bam_files == 1 ) {
                            #    ($aligned_bam) = keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}};
                            #     $bams_seen{$aligned_bam}++;
			    # }
    			    # elsif ( $num_bam_files > 1 ) {
                            #    ($aligned_bam) = sort keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}};     
                            #    my $bam;
                            #    foreach (sort keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}} ) {
                            #        $bam .= "$_ ";
                            #    }     
                            #    log_error( "Found $num_bam_files bam files for $donor $specimen $sample $bam" );
                            #    $bams_seen{$aligned_bam}++;
                            # }
                            # else {
                            #    log_error( "Could not find any aligned bam files for donor: $donor" );
                            #    $aligned_bam = 'NONE';
			    # }

                            my @dates = ();
  	                    if ( defined ($sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{date}) ) {
                                @dates = sort {$b <=> $a} @{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{date}};
    	                    }
                            else {
                                @dates = ( '0000-00-00', );
                            }
                            my $date = $dates[0];
                            # print the first 9 columns
                            print $FH "$study\t$project\t$donor\t$specimen\t$sample\t$type\t$aliquot_id\t$endpoint\n";
                            # test to see if what type of sample was aligned (either a 'Tumour' or a 'Normal')
			    # if ( $type eq 'Tumour' ) {
                                # it is a 'Tumour', so lets see if there is an entry in the use_cntls hash
                                # if ( defined ( $use_cntls{$aliquot_id}) ) {
                                    # Now, check to see if the 'Normal' that matches this Tumour has been processed in this batch
                                    # if ( $norm_aliquot_ids{$use_cntls{$aliquot_id}} ) {
                                        # YES, we found a normal ID corresponding, and it has been aligned
                                        # print $FH "\tYES\n";
                                    # }
                                    # else {
                                        # nope, the matching Normal to our Tumour sample has not been aligned yet
                                        # print $FH "\tNO\n";
				    # }
                                # }
                                # else {
                                #    print $FH "\tNOT FOUND\n";
			        # }
                            # }        
                            # else {
                                # if it failed that test up there, then it must be a 'Normal'
                                # so lets check to see if it was encountered, identified as a 'use_cntl'
                                # when we were parsing all those Tumour alignments
                                # if ( defined ( $norm_use_cntls{$aliquot_id} ) ) {
                                #    print $FH "\tYES\n";
			        # }
                                # else {
                                #    print $FH "\tNO\n";
			        # }
			    # } # close if/else test
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
    if ( $xml_file ) {
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
    }
    elsif ( $uri_list ) {
        open my $URIS, '<', $uri_list or die "Could not open $uri_list for reading!";
        @uris = <$URIS>;
        chomp( @uris );
        close $URIS;
    }
    foreach my $uri ( @uris ) {
        my ( $id ) = $uri =~ m/analysisFull\/([\w-]+)$/;
        # select the skip download option and the script will just use 
        # the Result XML files that were previously downloaded
        if ($skip_down) { 
            print STDERR "Skipping download, using previously downloaded xml/$id.xml\n";
        }
        elsif ( -e "xml/$id.xml" ) {
            print STDERR "Detected a previous copy of xml/$id.xml and will use that\n";
	}
        else {
            print STDERR "Now downloading file $id.xml from $uri\n";
            download($uri, "xml/$id.xml"); 
        } 
        my $adoc = undef;
        my $adoc2 = undef;

        # test to see if the download and everything worked
        if ( -e "xml/$id.xml" ) {
            # test for file contents to avoid XML parsing errors that kill script
            if ( -z "xml/$id.xml" ) {
                print STDERR "This XML file has zero size (i.e., is empty): $id.xml\n    SKIPPING\n\n";
                log_error( "SKIPPING xml file is empty and has zero size: $id.xml" );
                next;
	    }
        
            # create an XML::DOM object:
            $adoc = $parser->parsefile ("xml/$id.xml");
            # create ANOTHER XML::DOM object, using a differen Perl library
            $adoc2 = XML::LibXML->new->parse_file("xml/$id.xml");
	}
        else {
            print STDERR "Could not find this xml file: $id.xml\n    SKIPPING\n\n";
            log_error( "SKIPPING Could not find xml file: $id.xml" );
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
      my $mod_time = getVal($adoc, 'last_modified');
      my $analysisDataURI = getVal($adoc, 'analysis_data_uri');
      my $submitterAliquotId = getCustomVal($adoc2, 'submitter_aliquot_id');
      # my $aliquot_id = getVal($adoc, 'aliquot_id');
      # next unless checkvar( $aliquot_id, 'aliquot_id', $id, );
      my $use_control = getCustomVal($adoc2, "use_cntl");
      next unless checkvar( $use_control, 'use_control', $id, );
      # make sure that you are comparing lc vs lc (but not for the Normal samples)
      $use_control = lc($use_control) unless $use_control =~ m/N\/A/;
      my $dcc_specimen_type = getCustomVal($adoc2, 'dcc_specimen_type');
      next unless checkvar( $dcc_specimen_type, 'dcc_specimen_type', $id, );
      my $alignment = getVal($adoc, "refassem_short_name");
      my $total_lanes = getCustomVal($adoc2, "total_lanes");
      my $sample_uuid = getXPathAttr($adoc2, "refname", "//ANALYSIS_SET/ANALYSIS/TARGETS/TARGET/\@refname");
      my $libName = getVal($adoc, 'LIBRARY_NAME');
      my $libStrategy = getVal($adoc, 'LIBRARY_STRATEGY');
      my $libSource = getVal($adoc, 'LIBRARY_SOURCE');
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
      # there should only be two different types of alignment. For aligned samples there should be a single 
      # modification date

      push @{ $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{date} }, $mod_time; 
      $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{analysis_url} = $analysisDataURI; 
      $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{use_control} = $use_control; 
      $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{total_lanes} = $total_lanes;
      $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{sample_uuid} = $sample_uuid;
      $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{analysis_id} = $analysis_id;
      $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{aliquot_id} = $aliquot_id;

      # Check to see what is in use_control. If it is N/A then this is a Normal sample
      if ( $use_control && $use_control ne 'N/A' ) {
            # if it passes the test then it must be a 'Tumour', so we give it a 'type'
            # 'type' = 'Tumour'
            $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{type} = 'Tumour';
            # Now lets check to see if this type matches the contents of the dcc_specimen_type
            if ( $dcc_specimen_type =~ m/Normal/ ) {
                log_error( "MISMATCH dcc_specimen type in $id.xml OVERRIDING from Tumour to Normal" );            
                $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{type} = 'Normal';
            }            

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
        else {
            # otherwise, this is not a Tumour, so we give it a 'type'
            # 'type' = Normal
            $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{type} = 'Normal';
            # Now lets check to see if this type matches the contents of the dcc_specimen_type
            if ( $dcc_specimen_type =~ m/tumour/ ) {
                log_error( "MISMATCH dcc_specimen type in $id.xml OVERRIDING from Normal to Tumour" );            
                $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{type} = 'Tumour';
            }            

            # Add this aliquot ID to this list of all the 'Normal' 
            # aliquot ids encountered in this XML
            $norm_aliquot_ids{$aliquot_id}++;
        }

      my $files = readFiles($adoc);
      foreach my $file(keys %{$files}) {
          next if $file =~ m/\.bai/;
          $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{files}{$file}{size} = $files->{$file}{size}; 
          $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{files}{$file}{checksum} = $files->{$file}{checksum}; 
          $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{files}{$file}{localpath} = "$file"; 
          # $bams_seen{$file}{$sample_id}++;
      } # close foreach loop
  } # close for loop
  return($d);
} # close sub

sub readFiles {
  my ($d) = @_;
  my $ret = {};
  my $nodes = $d->getElementsByTagName ("file");
  my $n = $nodes->getLength;
  for (my $i = 0; $i < $n; $i++)
  {
    my $node = $nodes->item ($i);
	    my $currFile = getVal($node, 'filename');
	    my $size = getVal($node, 'filesize');
	    my $check = getVal($node, 'checksum');
            $ret->{$currFile}{size} = $size;
            $ret->{$currFile}{checksum} = $check;
  }
  return($ret);
} # close sub

sub getCustomVal {
    my ($dom2, $keys) = @_;
    my @keys_arr = split /,/, $keys;
    # this returns an array
    my @nodes = ($dom2->findnodes('//ANALYSIS_ATTRIBUTES/ANALYSIS_ATTRIBUTE'));
    for my $node ($dom2->findnodes('//ANALYSIS_ATTRIBUTES/ANALYSIS_ATTRIBUTE')) {
        my $i=0;
        # this also returns an array
        my @currKeys =  ($node->findnodes('//TAG/text()')); 
        my @count = $node->findnodes('//TAG/text()');
        my $count = scalar( @count );
        for my $currKey ($node->findnodes('//TAG/text()')) {
            $i++;
            my $keyStr = $currKey->toString();
            foreach my $key (@keys_arr) {
                if ($keyStr eq $key) {
                    my $j=0;
                    my @count_2 = $node->findnodes('//VALUE/text()');
                    my $count_2 = scalar(@count_2);
                    unless ( $count == $count_2 ) {
                        log_error( "Number of Keys does not match number of values in an XML file" );
		    }
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
    return 0;
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

sub log_error {
    my ($mesg) = @_;
    open my ($ERR), '>>', 'data_freeze_2.0_error_log_' . $timestamp . '.txt' or die;
    print $ERR "$mesg\n";
    close $ERR;
    $error_log++;
} # close sub

sub checkvar {
    my ( $var, $name, $id, ) = @_;
    unless ( $var ) {
        print STDERR "The value in \$" . "$name is False; skipping $id\n";
        log_error( "SKIPPED $id.xml because \$" . "$name was False");
        return 0;
    } # close unless test
    return 1;
} # close sub


__END__

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

