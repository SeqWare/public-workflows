#!/usr/bin/perl
#
# File: control_string_identifier.pl by Marc Perry
# based on a fork of my gnos_report_generator.pl script
# 
# DESCRIPTION
# A tool for trying to determine which field a data submitting group is using
# in their PCAP XML files in the 'use_cntl' field
#
# This script is designed to take a list of xml files, specified on the command line
# extracting the use_cntl field from the Tumour
# returned by cgquery, and use it to either download, and 
# then parse, all of the GNOS xml files listed in the data.xml file
# OR, if you have already downloaded the xmls, then the script
# Will parse them.
#
# Last Modified: 2014-05-18, Status: works as advertised

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
my $report_name = "workflow_decider_report_gn";
my $skip_upload = "true";
my $upload_results = 0;
my $xml_file = undef;

my @repos = qw( bsc dkfz ebi etri osdc );

my %urls = ( bsc   => "https://gtrepo-bsc.annailabs.com",
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
my %aligned_bams_seen = ();
my %unaligned_bams_seen = ();
my %problems = ();
my $single_specimens = {};
my $two_specimens = {};
my $many_specimens = {};

# MDP: these are the two that you may really want to use:
# --gnos-url (one of the six choices above)
# --skip-meta-download 0 (the default is '1' or true, and the script will run much faster
# by working with the previously downloaded xml files)
#
#   print "\t--gnos-url           a URL for a GNOS server, e.g. https://gtrepo-ebi.annailabs.com\n";
#   print "\t--skip-meta-download use the previously downloaded XML from GNOS, only useful for testing\n";

GetOptions("gnos-url=s" => \$gnos_url, "xml-file=s" => \$xml_file, "sample=s" => \$specific_sample, "ignore-lane-count" => \$ignore_lane_cnt, "skip-meta-download" => \$skip_down, "report=s" => \$report_name, "upload-results" => \$upload_results);

my $usage = "USAGE: $0 --skip-meta-download --xml-file <data.xml>";

die $usage unless $xml_file;

# capture the name of the centre from the command line using GetOpt::Long
# and use that string as a hash key to get the URL that you want
# $gnos_url = $urls{$gnos_url};


##############
# MAIN STEPS #
##############
print STDERR scalar localtime, "\n\n";

my @now = localtime();
my $timestamp = sprintf( "%04d_%02d_%02d_%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], );

$report_name .= '_' . $timestamp . '.txt';

# output data table
open my $FH, '>', 'table_report__' . $timestamp . '.tsv' or die "Could not open table for writing: $!";

# output report file

# READ INFO FROM GNOS
my $sample_info = read_sample_info();

# SCHEDULE SAMPLES
# now look at each sample, see if it's already schedule, launch if not and a cluster is available, and then exit
schedule_samples($sample_info);

foreach my $bam ( sort keys %aligned_bams_seen ) {
    if ( $aligned_bams_seen{$bam} > 1 ) {
        log_error( "Found multiple donors using this aligned bam: $bam" ); 
    }
} # close foreach loop

foreach my $bam ( sort keys %unaligned_bams_seen ) {
    if ( $unaligned_bams_seen{$bam} > 1 ) {
        log_error( "Found multiple donors using this unaligned bam: $bam" ); 
    }
} # close foreach loop


print STDERR "WARNING: Logged $error_log errors in error_log_gnos_report.txt stamped with $timestamp\n" if $error_log;

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
    #################################################
    # >>>> Below here pasted in from pcap_data_freeze_alignment_report_generator.pl
    #################################################
    foreach my $project (sort keys %{$sample_info}) {
        if ( $project ) {
            print STDERR "Now processing XML files for $project\n";
        }
        # Iteratively parse the data structure built from all of the XML files, and parse them out
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
    # one of these three hash references (unless the specimen field was blank)
    # Test each hash reference to see if it contains any data, if it does
    # then use the process_specimens subroutine to extract that data into a table
    # and print out each table into individual files:
    if ( keys %{$single_specimens} ) {
        open my $FH1, '>', 'gnos_report_for_unpaired_specimens_' . $timestamp . '.tsv' or die;
        process_specimens( $single_specimens, $FH1, );
        close $FH1;
    }

    if ( keys %{$two_specimens} ) {
        open my $FH2, '>', 'gnos_report_for_paired_specimens_' . $timestamp . '.tsv' or die;
        process_specimens( $two_specimens, $FH2, );
        close $FH2;
    }

    if ( keys %{$many_specimens} ) {
        open my $FH3, '>', 'gnos_report_for_many_specimens_' . $timestamp . '.tsv' or die;
        process_specimens( $many_specimens, $FH3, );
        close $FH3;
    }
} # close sub


# N.B. I cut and pasted this subroutine from my pcap_data_freeze_report_generator.pl script
# And in that script I was only interested in the aligned bam files/samples, so I think I am 
# going to have to modify the logic here to get it to work as desired for non-aligned as well
# Lets stop and work it out now instead of on the fly 
# 
# I can imagine 4 types of submissions: Tumour unaligned, Tumour aligned, Normal unaligned, Normal aligned
# Data structure for 1 donor could have 1 or 2 specimens, but I have sorted that out above (in theory)
# So if there is only a single specimen, that could be Normal OR Tumour but it could have both an aligned
# and an unaligned, so that is two rows in the output table--it could have two rows, but it may not
# Okay thus far I don't see anything I need to change (yet), because I parsed them above into
# three different classes: 1 donor, 1 specimen, 1 donor, 2 specimens, 1 donor, 3 specimens (this last is
# likely an error, but may have to tweak this later
#

sub process_specimens {
    my $sample_info = shift @_;
    my $FH = shift @_;
    print $FH "Project\tDonor ID\tSpecimen ID\tSample ID\tNormal/Tumour\tAlignment\tDate\tAnalysis ID\tNumber of bams\taligned bam file\tpair aligned\n";
    foreach my $project (sort keys %{$sample_info}) {
        foreach my $donor ( keys %{$sample_info->{$project}} ) {
            foreach my $specimen (keys %{$sample_info->{$project}{$donor}}) {
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

                            # I need to change the logic here, because before I was looking for donor specimen sample
                            # trios that had more than 1 aligned bams, but now I want to change it and ask
                            # if a single bam file appears in more than one submission (as well)
                            my $aligned_bam = q{};
                            my $num_bam_files = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{bams_count};
                            # Test and see if there is only a single bam file
              	            if ( $num_bam_files == 1 and $alignment ne 'unaligned' ) {
                                ($aligned_bam) = keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}};
                                $aligned_bams_seen{$aligned_bam}++;
			    }
    			    elsif ( $num_bam_files > 1 and $alignment ne 'unaligned' ) {
                                foreach (sort keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}} ) {
                                    $aligned_bams_seen{$_}++;
                                    $aligned_bam .= $_;
                                }     
                                log_error( "Found $num_bam_files aligned bam files for $donor $specimen $sample" );
                            }
                            else {
                                foreach (sort keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}} ) {
                                    $unaligned_bams_seen{$_}++;
                                }     
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
                            # This is the header that this script originally used
                            # print $FH "$project\t$donor\t$specimen\t$sample\t$alignment\t$date\t$num_bam_files\t$aligned_bam\t$aliquot_id";
                            # print the first 10 columns
                            print $FH "$project\t$donor\t$specimen\t$sample\t$type\t$alignment\t$date\t$analysis_id\t$num_bam_files\t$aligned_bam";
                            # see if the use_cntl field is filled in in a helpful way
                            # we would only expect this field to be filled in only for the 'Tumour' samles
			    if ( $type eq 'Tumour' ) {
                                # this specimen and sample is a 'Tumour', see if there is an entry in the use_cntls hash:
                                if ( defined ( $use_cntls{$aliquot_id}) ) {
                                    # Now, check to see if any of the 'Normal' bams that match this Tumour 
                                    # have been uploaded and processed in this batch of XML files
                                    if ( $norm_aliquot_ids{$use_cntls{$aliquot_id}} ) {
                                        # YES, we found a corresponding normal ID
                                        print $FH "\tYES\n";
                                    }
                                    else {
                                        # nope, the matching Normal to our Tumour sample has not been
                                        # uploaded yet (presumably these would be weeded out of the 2 specimens
                                        # group by the parsing above
                                        print $FH "\tNO\n";
				    }
                                }
                                else {
                                    print $FH "\tNOT FOUND\n";
			        }
                            }        
                            else {
                                # if it failed that test up there, then it must be a 'Normal'
                                # so lets check to see if it was encountered, and identified as a 'use_cntl'
                                # when we were parsing all those Tumour specimens
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

  # read in the xml file returned by the cgquery command
  my $doc = $parser->parsefile("$xml_file");
  my $nodes = $doc->getElementsByTagName ("Result");
  my $n = $nodes->getLength;

  # iterate over the Result XML files that were downloaded into the 
  # xml/ directory  
  for (my $i = 0; $i < $n; $i++)
  {
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
      # create ANOTHER XML::DOM object, using a differen Perl library
      my $adoc2 = XML::LibXML->new->parse_file("xml/data_$i.xml");
      my $project = getCustomVal($adoc2, 'dcc_project_code');
      my $donor_id = getCustomVal($adoc2, 'submitter_donor_id');
      my $specimen_id = getCustomVal($adoc2, 'submitter_specimen_id');
      my $sample_id = getCustomVal($adoc2, 'submitter_sample_id');
      # Require a project, donor, specimen, and sample to proceed
      next unless ( $project && $donor_id && $specimen_id && $sample_id );
      my $analysis_id = getVal($adoc, 'analysis_id');
      my $mod_time = getVal($adoc, 'last_modified');
      my $analysisDataURI = getVal($adoc, 'analysis_data_uri');
      my $submitterAliquotId = getCustomVal($adoc2, 'submitter_aliquot_id,submitter_sample_id');
      my $aliquot_id = getVal($adoc, 'aliquot_id');
      my $use_control = getCustomVal($adoc2, "use_cntl");
      my $alignment = getVal($adoc, "refassem_short_name");
      my $total_lanes = getCustomVal($adoc2, "total_lanes");
      my $sample_uuid = getXPathAttr($adoc2, "refname", "//ANALYSIS_SET/ANALYSIS/TARGETS/TARGET/\@refname");
      my $libName = getVal($adoc, 'LIBRARY_NAME');
      my $libStrategy = getVal($adoc, 'LIBRARY_STRATEGY');
      my $libSource = getVal($adoc, 'LIBRARY_SOURCE');

      # get files
      # now if these are defined then move onto the next step
        # in the data structure each Analysis Set is sorted by it's ICGC DCC project code, then the combination of
        # donor, specimen, and sample that should be unique identifiers
        # there should only be to different types of alignment. For aligned samples there should be a single 
        # modification date, for the unaligned, each bam file will have a slightly different one, so
        # we will take the most recent one (sort the array later)
        push @{ $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{date} }, $mod_time; 
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{analysis_url} = $analysisDataURI; 
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{library_strategy} = $libStrategy; 
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{library_source} = $libSource; 
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{use_control} = $use_control; 
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{total_lanes} = $total_lanes;
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{sample_uuid} = $sample_uuid;
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{analysis_id} = $analysis_id;
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{aliquot_id} = $aliquot_id;
        # First check to see if there is a value in use_cntl
        # then check to see if it is N/A.  If it is N/A then this is a Normal sample
        if ( $use_control && $use_control ne 'N/A' ) {
            # if it passes the test then it must be a 'Tumour', so we give it a 'type'
            # 'type' = 'Tumour'
            $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{type} = 'Tumour';
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
      }
  }

  # Avoid memory leaks - cleanup circular references for garbage collection
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
    open my ($ERR), '>>', 'error_log_gnos_report_' . $timestamp . '.txt' or die;
    print $ERR "$mesg\n";
    close $ERR;
    $error_log++;
} # close sub

__END__

