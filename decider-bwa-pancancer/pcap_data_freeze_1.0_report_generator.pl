#!/usr/bin/perl
#
# File: pcap_data_freeze_1.0_report_generator.pl
# 
# based on, and forked from my previous script named: gnos_report_generator__2014_05_01.pl
#
# Last Modified: 2014-06-11, Status: basically working

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
# my $gnos_url = "https://gtrepo-ebi.annailabs.com";
my $gnos_url = q{};
my $cluster_json = "";
my $working_dir = "decider_tmp";
my $specific_sample;
my $test = 1;
my $ignore_lane_cnt = 0;
my $force_run = 0;
my $threads = 8;
my $report_name = q{};
my $seqware_setting = "seqware.setting";
# by default skip the upload of results back to GNOS
my $skip_upload = "true";
my $upload_results = 0;
my $xml_file = undef;

my @repos = qw( bsc cghub dkfz ebi etri osdc );

my %urls = ( bsc   => "https://gtrepo-bsc.annailabs.com",
             cghub => "https://cghub.ucsc.edu",
             dkfz  => "https://gtrepo-dkfz.annailabs.com",
             ebi   => "https://gtrepo-ebi.annailabs.com",
             etri  => "https://gtrepo-etri.annailabs.com",
             osdc  => "https://gtrepo-osdc.annailabs.com",
             riken => "https://gtrepo-riken.annailabs.com",
);

# a hash only used to store the analysis_ids of
# alignments
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
                    'CESC-US' => "Cervical Squamous Cell Carcinoma - TCGA, US",
                    'CLLE-ES' => "Chronic Lymphocytic Leukemia - CLL with mutated and unmutated IgVH",
                    'COAD-US' => "Colon Adenocarcinoma - TCGA, US",
                    'EOPC-DE' => "Prostate Cancer - Early Onset",
                    'ESAD-UK' => "Esophageal adenocarcinoma",
                    'GBM-US'  => "Brain Glioblastoma Multiforme - TCGA, US",
                    'HNSC-US' => "Head and Neck Squamous Cell Carcinoma - TCGA, US",
                    'KICH-US' => "Kidney Chromophobe - TCGA, US",
                    'KIRC-US' => "Kidney Renal Clear Cell Carcinoma - TCGA, US",
                    'KIRP-US' => "Kidney Renal Papillary Cell Carcinoma - TCGA, US",
                    'LAML-US' => "Acute Myeloid Leukemia - TCGA, US",
                    'LGG-US'  => "Brain Lower Grade Gliona - TCGA, US",
                    'LICA-FR' => "Liver Cancer - Hepatocellular carcinoma",
                    'LIHC-US' => "Liver Hepatocellular carcinoma - TCGA, US",
                    'LIRI-JP' => "Liver Cancer - Hepatocellular carcinoma (Virus associated)",
                    'LUAD-US' => "Lung Adenocarcinoma - TCGA, US",
                    'MALY-DE' => "Malignant Lymphoma",
                    'OV-US'   => "Ovarian Serous Cystadenocarcinoma - TCGA, US",
                    'PACA-AU' => "Pancreatic Cancer - Ductal adenocarcinoma",
                    'PACA-CA' => "Pancreatic Cancer - Ductal adenocarcinoma - CA",
                    'PBCA-DE' => "Pediatric Brain Tumors",
                    'PRAD-US' => "Prostate Adenocarcinoma - TCGA, US",
                    'READ-US' => "Rectum Adenocarcinoma - TCGA, US",
                    'SARC-US' => "Sarcoma - TCGA, US",
                    'SKCM-US' => "Skin Cutaneous melanoma - TCGA, US",
                    'STAD-US' => "Gastric Adenocarcinoma - TCGA, US",
                    'THCA-US' => "Head and Neck Thyroid Carcinoma - TCGA, US",
                    'UCEC-US' => "Uterine Corpus Endometrial Carcinoma- TCGA, US",
);

GetOptions("gnos-url=s" => \$gnos_url, "xml-file=s" => \$xml_file, "cluster-json=s" => \$cluster_json, "working-dir=s" => \$working_dir, "sample=s" => \$specific_sample, "test" => \$test, "ignore-lane-count" => \$ignore_lane_cnt, "force-run" => \$force_run, "threads=i" => \$threads, "skip-meta-download" => \$skip_down, "report=s" => \$report_name, "settings=s" => \$seqware_setting, "upload-results" => \$upload_results);

my $usage = "USAGE: $0 --xml-file <data.xml>";
die $usage unless $xml_file;

##############
# MAIN STEPS #
##############

print STDERR scalar localtime, "\n\n";

my @now = localtime();

# rearrange the following to suit your stamping needs.
# it currently generates YYYYMMDDhhmmss
my $timestamp = sprintf("%04d_%02d_%02d_%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1],);

# READ CLUSTER INFO AND RUNNING SAMPLES
# my ($cluster_info, $running_samples) = read_cluster_info($cluster_json);
my ($cluster_info, $running_samples);

# READ INFO FROM GNOS
my $sample_info = read_sample_info();

# SCHEDULE SAMPLES
# now look at each sample, see if it's already schedule, launch if not and a cluster is available, 
# and then exit
schedule_samples($sample_info);

foreach my $bam ( sort keys %bams_seen ) {
    if ( $bams_seen{$bam} > 1 ) {
        log_error( "Found multiple donors using this aligned bam: $bam" ); 
    }
    #if ( $bams_seen{$bam} > 1 ) {
    #    log_error( "This aligned bam file appears in ". $bams_seen{$bam} . " files: $bam" );
    #}
} # close foreach loop

print STDERR "WARNING: Logged $error_log errors in error_log_aligned.txt stamped with $timestamp\n" if $error_log;

END {
    no integer;
    printf( STDERR "Running time: %5.2f minutes\n",((time - $^T) / 60));
} # close END block

###############
# SUBROUTINES #
###############

sub schedule_samples {
    my $rec_no = 0;
    die "\$sample_info hashref is empty!" unless ($sample_info);

    foreach my $project (sort keys %{$sample_info}) {
        if ( $project ) {
            print STDERR "Now processing XML files for $project\n";
        }
        # Parse the data structure built from all of the XML files, and parse them out
        # into three categories--and three new data structures
        foreach my $donor ( keys %{$sample_info->{$project}} ) {
            # skip processing this row if no donor name was extracted from the XML file
            next unless $donor;
            my $num_of_specimens = scalar( keys %{$sample_info->{$project}{$donor}} );
            if ( $num_of_specimens == 1 ) {
                # This cannot be paired if there is only a single specimen
                $single_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};
	    }
            elsif ( $num_of_specimens == 2 ) {
                # This might be paired because there are exactly 2 specimens for this donor
                $two_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};      
            } 
	    elsif ( $num_of_specimens > 2 ) {
                # This has more than 2 specimens, probably some duplicated samples
                log_error( "Found more than two specimens for this donor: $donor" );
                $many_specimens->{$project}{$donor} = $sample_info->{$project}{$donor};
	    }
            else {
                # No specimens, skip it
                log_error( "No specimens found for Project: $project Donor: $donor" );
                next;
	    }
	} # close foreach $donor
    } # close foreach project

    # At this point all of the data parsed from the xml files should be allocated into
    # one of these three hash references (unless the specimen field was blank
    # Test each hash reference to see if it contains any data, if it does
    # then use the process_specimens subroutine to extract that data into a table
    # and print out each table into individual files:
    if ( keys %{$single_specimens} ) {
        open my $FH1, '>', 'unpaired_specimen_alignments_' . $timestamp . '.tsv' or die;
        process_specimens( $single_specimens, $FH1, );
        close $FH1;
    }

    if ( keys %{$two_specimens} ) {
        open my $FH2, '>', 'paired_alignments_' . $timestamp . '.tsv' or die;
        process_specimens( $two_specimens, $FH2, );
        close $FH2;
    }

    if ( keys %{$many_specimens} ) {
        open my $FH3, '>', 'many_specimen_alignments_' . $timestamp . '.tsv' or die;
        process_specimens( $many_specimens, $FH3, );
        close $FH3;
    }
} # close sub

sub process_specimens {
    my $sample_info = shift @_;
    my $FH = shift @_;
    my $endpoint = $urls{$gnos_url};

    print $FH "Study\tProject Code\tDonor ID\tSpecimen/Sample ID\tSample/Aliquot ID\tNormal/Tumour designation\tAnalyzed Sample/Aliquot GUUID\tGNOS endpoint\tAnalysis ID\tbam file\tpair aligned\n";
    foreach my $project (sort keys %{$sample_info}) {
        my $study = $study_names{$project};
        $study = "NO STUDY FOUND" unless $study;     
        foreach my $donor ( keys %{$sample_info->{$project}} ) {
            foreach my $specimen (keys %{$sample_info->{$project}{$donor}}) {
                # MDPQ: Why are these hashrefs here? What do we use them for
                my $d = {};
                my $aligns = {};
                foreach my $sample ( keys %{$sample_info->{$project}{$donor}{$specimen}} ) {
                    foreach my $alignment ( keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}} ) {
                        next if $alignment eq 'unaligned';
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

                            my @dates = ();
  	                    if ( defined ($sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{date}) ) {
                                @dates = sort {$b <=> $a} @{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{date}};
    	                    }
                            else {
                                @dates = ( '0000-00-00', );
                            }
                            my $date = $dates[0];
                            # print the first 9 columns
                            print $FH "$study\t$project\t$donor\t$specimen\t$sample\t$type\t$aliquot_id\t$endpoint\t$analysis_id\t$aligned_bam";
                            # test to see if what type of sample was aligned (either a 'Tumour' or a 'Normal')
			    if ( $type eq 'Tumour' ) {
                                # it is a 'Tumour', so lets see if there is an entry in the use_cntls hash
                                if ( defined ( $use_cntls{$aliquot_id}) ) {
                                    # Now, check to see if the 'Normal' that matches this Tumour has been processed in this batch
                                    if ( $norm_aliquot_ids{$use_cntls{$aliquot_id}} ) {
                                        # YES, we found a normal ID corresponding, and it has been aligned
                                        print $FH "\tYES\n";
                                    }
                                    else {
                                        # nope, the matching Normal to our Tumour sample has not been aligned yet
                                        print $FH "\tNO\n";
				    }
                                }
                                else {
                                    print $FH "\tNOT FOUND\n";
			        }
                            }        
                            else {
                                # if it failed that test up there, then it must be a 'Normal'
                                # so lets check to see if it was encountered, identified as a 'use_cntl'
                                # when we were parsing all those Tumour alignments
                                if ( defined ( $norm_use_cntls{$aliquot_id} ) ) {
                                    print $FH "\tYES\n";
			        }
                                else {
                                    print $FH "\tNO\n";
			        }
			    } # close if/else test
		    } # close foreach my alignment
		} # close foreach my sample
	    } # close foreach my specimen
	} # close foreach my donor
    } # close foreach my project
} # close sub

sub read_sample_info {
    my $d = {};
    my $type = q{};

    # PARSE XML
    my $parser = new XML::DOM::Parser;

    my $doc = $parser->parsefile("$xml_file");
    my $nodes = $doc->getElementsByTagName ("Result");
    my $n = $nodes->getLength;

    # iterate over the Result XML files that were downloaded into the 
    # xml/ directory  
    for (my $i = 0; $i < $n; $i++) {
        my $node = $nodes->item ($i);
        my $aurl = getVal($node, "analysis_full_uri"); 
        if($aurl =~ /^(.*)\/([^\/]+)$/) {
            $aurl = $1."/".lc($2);
        } 
        else { 
            next;
        }
        # set the skip download variable to '1' and the script will just use 
        # the Result XML files that were previousluy downloaded
        if (!$skip_down) { 
            print STDERR "Now downloading file data_$i.xml from $aurl\n";
            download($aurl, "xml/data_$i.xml"); 
        }
        else {
            print STDERR "Parsing previously downloaded data_$i.xml\n";
        } 

      # create an XML::DOM object:
      my $adoc = $parser->parsefile ("xml/data_$i.xml");
      my $alignment = getVal($adoc, "refassem_short_name");
      # immediately test if this sample is 'unaligned', no need to process any further
      if ( $alignment ) {
          next if $alignment eq 'unaligned';
      }
      else {
          log_error( "Could not find an alignment for data_${i}.xml, skipping" );
          next;
      }
      # create ANOTHER XML::DOM object, using a different Perl library
      my $adoc2 = XML::LibXML->new->parse_file("xml/data_$i.xml");
      my $project = getCustomVal($adoc2, 'dcc_project_code');
      # 2014-06-11 N.B. This script ignores any files that do not contained
      # aligned bams, and so we would expect a single analysis_id that
      # would uniquely identify this one XML file that is currently being
      # parsed:
      my $analysis_id = getVal($adoc, 'analysis_id');
      my $study = getVal($adoc, 'study');
      my $mod_time = getVal($adoc, 'last_modified');
      my $analysisDataURI = getVal($adoc, 'analysis_data_uri');
      # $submitterAliquotId will contain whichever matches first
      my $submitterAliquotId = getCustomVal($adoc2, 'submitter_aliquot_id,submitter_sample_id');
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

      my $donor_id = getCustomVal($adoc2, 'submitter_donor_id');
      my $specimen_id = getCustomVal($adoc2, 'submitter_specimen_id');
      my $sample_id = getCustomVal($adoc2, 'submitter_sample_id');
      my $use_control = getCustomVal($adoc2, "use_cntl");

      my $total_lanes = getCustomVal($adoc2, "total_lanes");
      my $sample_uuid = getXPathAttr($adoc2, "refname", "//ANALYSIS_SET/ANALYSIS/TARGETS/TARGET/\@refname");

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

      # First check to see if there is a value in use_cntl
      # then check to see if it is N/A.  If it is N/A then this is a Normal sample
      if ( $use_control && $use_control ne 'N/A' ) {
          # if it passes the test then it must be a 'Tumour', so we assign it a 'type'
          # in this case the 'type' = 'Tumour'
          $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{type} = 'Tumour';
          # keep track of the correct use_cntl for this Tumor Sample by storing
          # the information in the %use_cntls hash, where the hash key is the 
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

  $doc->dispose;
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
    open my ($ERR), '>>', 'error_log_aligned_' . $timestamp . '.txt' or die;
    print $ERR "$mesg\n";
    close $ERR;
    $error_log++;
} # close sub

__END__

