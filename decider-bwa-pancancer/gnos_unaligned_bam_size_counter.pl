#!/usr/bin/perl
#
# File: gnos_unaligned_bam_size_counter.pl (derived almost entirely from my previous script 
# named gnos_report_generator.pl)
# 
# DESCRIPTION
# A tool for reporting on the sizes of unaligned bam files in a GNOS repository
#
# This script is designed to take the data.xml file
# returned by cgquery, and use it to either download, and 
# then parse, all of the GNOS xml files listed in the data.xml file
# OR, if you have already downloaded the xmls, then the script
# Will parse them.
#
# Last Modified: 2014-08-25, Status: works as advertised

use strict;
# use warnings;
use XML::DOM;
use Data::Dumper;
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
my %aligned_bams_seen = ();
my %unaligned_bams_seen = ();
my %multiple_aligned_bams = ();
my %problems = ();
my $single_specimens = {};
my $two_specimens = {};
my $many_specimens = {};

GetOptions("gnos-url=s" => \$gnos_url, "xml-file=s" => \$xml_file, "sample=s" => \$specific_sample, "skip-meta-download" => \$skip_down, "uri-list=s" => \$uri_list, );

# In the data_live XML file downloaded by cgquery one such XML element looks like this:
# <analysis_full_uri>https://gtrepo-ebi.annailabs.com/cghub/metadata/analysisFull/c74231a4-f0b3-11e3-bddc-c84f2e14b9ce</analysis_full_uri>
# https://gtrepo-ebi.annailabs.com/cghub/metadata/analysisFull/c74231a4-f0b3-11e3-bddc-c84f2e14b9ce
# https://gtrepo-ebi.annailabs.com/cghub/metadata/analysisFull/

my $usage = "USAGE: There are two ways to runs this script:\nEither provide the name of an XML file on the command line:\n$0 --xml-file <data.xml> --gnos-url <abbrev>\nOR provide the name of a file that contains a list of GNOS repository analysis_full_uri links:\n$0 --uri-list <list.txt> --gnos-url <abbrev>.\n\nThe script will also generate this message if you provide both an XML file AND a list of URIs\n";

die $usage unless $xml_file or $uri_list;
die $usage if $xml_file and $uri_list;
die $usage unless $gnos_url;

##############
# MAIN STEPS #
##############
print STDERR scalar localtime, "\n";

my @now = localtime();
my $timestamp = sprintf( "%04d_%02d_%02d_%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], );

# STEP 1. READ INFO FROM GNOS
# This subroutine call returns a hashref
my $sample_info = read_sample_info();

# STEP 2. MAP SAMPLES
# Process the data structure that has been passed in and print out
# a table showing the donors, specimens, samples, number of bam files, alignment
# status, etc.
map_samples($sample_info);

# STEP 3. QC
# now review to see if any aligned bam files were listed
# in the metadata for more than one single donor
foreach my $bam ( sort keys %aligned_bams_seen ) {
    if ( $aligned_bams_seen{$bam} > 1 ) {
        log_error( "Found multiple donors using this aligned bam: $bam" ); 
    }
} # close foreach loop

# now review to see if any unaligned bam files were listed
# in the metadata for more than one single donorp
foreach my $bam ( sort keys %unaligned_bams_seen ) {
    if ( $unaligned_bams_seen{$bam} > 1 ) {
        log_error( "Found multiple donors using this unaligned bam: $bam" ); 
    }
} # close foreach loop

# if any errors were detected during the run, notify the user
print STDERR "WARNING: Logged $error_log errors in ${gnos_url}_error_log_gnos_report.txt stamped with $timestamp\n" if $error_log;

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
                log_error( "No specimens found for Project: $project Donor: $donor    SKIPPING" );
                next;
	    }
           
	    if ( $many_tumours ) {
                log_error( "Found more than two Tumour specimens for this donor: $donor" );
	    }

	} # close foreach $donor
    } # close foreach project

    # At this point all of the data parsed from the xml files should be allocated into
    # one of these three hash references (unless the specimen field was blank)
    # Test each hash reference to see if it contains any data, if it does
    # then use the process_specimens subroutine to extract that data into a table
    # and print out each table into individual files:
    if ( keys %{$single_specimens} ) {
        open my $FH1, '>', "${gnos_url}_gnos_unaligned_bamsizes_for_unpaired_specimens_" . $timestamp . '.tsv' or die;
        process_specimens( $single_specimens, $FH1, );
        close $FH1;
    }

    if ( keys %{$two_specimens} ) {
        open my $FH2, '>', "${gnos_url}_gnos_unaligned_bamsizes_for_paired_specimens_" . $timestamp . '.tsv' or die;
        process_specimens( $two_specimens, $FH2, );
        close $FH2;
    }

    if ( keys %{$many_specimens} ) {
        open my $FH3, '>', "${gnos_url}_gnos_unaligned_bamsizes_for_many_specimens_" . $timestamp . '.tsv' or die;
        process_specimens( $many_specimens, $FH3, );
        close $FH3;
    }
} # close sub

# I can imagine 4 types of submissions: Tumour unaligned, Tumour aligned, Normal unaligned, Normal aligned
# Data structure for 1 donor could have 1 or 2 specimens, but I have sorted that out above (in theory)
# So if there is only a single specimen, that could be Normal OR Tumour but it could have both an aligned
# and an unaligned, so that is two rows in the output table--it could have two rows, but it may not

sub process_specimens {
    my $sample_info = shift @_;
    my $FH = shift @_;
    print $FH "Project\tDonor ID\tSpecimen ID\tSample ID\tNormal/Tumour\tAliquot ID\tAnalysis ID\tDate\tbam file\tSize\n";
    foreach my $project (sort keys %{$sample_info}) {
        foreach my $donor ( keys %{$sample_info->{$project}} ) {
            my %types = ();
            my @specimens = keys %{$sample_info->{$project}{$donor}};
            my $specimen_count = scalar( @specimens );
            foreach my $specimen ( @specimens ) {
                foreach my $sample ( keys %{$sample_info->{$project}{$donor}{$specimen}} ) {
                    foreach my $alignment ( keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}} ) {
                        my $type = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{type};
                        $types{$type}++;
                        my $aliquot_id = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{aliquot_id};
                        my $analysis_id = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{analysis_id};
                        my $i = 0;
                        foreach my $bam (keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}}) {
	                    my $date = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{date}[$i];
                            $i++;
                            my $size = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}{$bam}{size};
                            print $FH "$project\t$donor\t$specimen\t$sample\t$type\t$aliquot_id\t$analysis_id\t$date\t$bam\t$size\n";
                        } # close foreach my $bam loop
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

        # This script is all about tabulating the sizes of the uploaded unaligned bam files
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
        # Previous version
        # my $submitterAliquotId = getCustomVal($adoc2, 'submitter_aliquot_id');
        my $submitterAliquotId = getVal($adoc, 'submitter_aliquot_id');
        my $aliquot_id = getVal($adoc, 'aliquot_id');
        next unless checkvar( $aliquot_id, 'aliquot_id', $id, );
        my $use_control = getCustomVal($adoc2, "use_cntl");
        next unless checkvar( $use_control, 'use_control', $id, );
        # make sure that you are comparing lc vs lc (but not for the Normal samples)
        $use_control = lc($use_control) unless $use_control =~ m/N\/A/;
        my $dcc_specimen_type = getCustomVal($adoc2, 'dcc_specimen_type');
        next unless checkvar( $dcc_specimen_type, 'dcc_specimen_type', $id, );
        # my $alignment = getVal($adoc, "refassem_short_name");
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
        # We already checked to see if use_cntl had a valid value
        # (First check to see if there is a value in use_cntl)
        # then check to see if it is N/A.  If it is N/A then this is a Normal sample
        if ( $use_control && $use_control ne 'N/A' ) {
            # if it passes the test then it must be a 'Tumour', so we give it a 'type'
            # 'type' = 'Tumour'
            $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{type} = 'Tumour';
            # Now lets check to see if this type matches the contents of the dcc_specimen_type
            if ( $dcc_specimen_type =~ m/Normal/ ) {
                log_error( "MISMATCH dcc_specimen type in $id.xml OVERRIDING from Tumour to Normal" );            
                $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{type} = 'Normal';
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
        }
        $doc->dispose;
    }
    # print "\n", Data::Dumper->new([\$d],[qw(d)])->Indent(1)->Quotekeys(0)->Dump, "\n";
    # exit;
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
  if ( defined($node) ) {
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
    # recall that $out contains both the path and the 
    # filename
    # if ( -e "$out" ) {
    #     print STDERR "Detected a previous copy of xml/$out Skipping\n";
    #     return;
    # }
    # -O specifies the name of the desired output file
    # -q equals quiet, it suppresses all of the wget STDERR
    # -nc means no-clobber, it will not overwrite a file that is already
    # in that directory
    # Nope, this -nc is not working as I anticipated
    print STDERR ">>>>>>  Attempting to download $out using wget\n";
    my $r = system("wget -nc -q -O $out $url");
    if ($r) {
        print STDERR ">>>>>>  wget download FAILED\n";
        $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
        print STDERR ">>>>>>>>  Attempting to download $out using lwp\n";
        $r = system("lwp-download $url $out");
        if ($r) {
	    print STDERR "ERROR DOWNLOADING: $url\n";
	    exit(1);
        }
    }
} # close sub

sub log_error {
    my ($mesg) = @_;
    open my ($ERR), '>>', "${gnos_url}_error_log_from_gnos_unaligned_bamsizes_" . $timestamp . '.txt' or die;
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


__END__

According to my manual review of the XML::DOM module (specifically, the DOM.pm file),
The following four packages all have a separate dispose method:

XML::DOM::Node
XML::DOM::Element
XML::DOM::Document
XML::DOM::DocumentType

Son-of-a-bitch, that seems to have helped quite a bit!

