#!/usr/bin/perl
#
# File: gnos_report_generator__2014_05_12.pl
# Last Modified: 2014-05-12, Status: works as advertised

use strict;
use XML::DOM;
use Data::Dumper;
use JSON;
use Getopt::Long;
use XML::LibXML;
use Cwd;

# DESCRIPTION
# A tool for reporting on the total number of aligned and unaligned
# bam files in a GNOS repository

#############
# VARIABLES #
#############

my $skip_down = 0;
my $gnos_url = q{};
my $cluster_json = "";
my $working_dir = "decider_tmp";
my $specific_sample;
my $test = 1;
my $ignore_lane_cnt = 0;
my $force_run = 0;
my $threads = 8;
my $report_name = "workflow_decider_report_gn";
my $seqware_setting = "seqware.setting";
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
my %bams_seen = ();
my %problems = ();

# MDP: these are the two that you may really want to use:
# --gnos-url (one of the six choices above)
# --skip-meta-download 0 (the default is '1' or true, and the script will run much faster
# by working with the previously downloaded xml files)
#
#   print "\t--gnos-url           a URL for a GNOS server, e.g. https://gtrepo-ebi.annailabs.com\n";
#   print "\t--skip-meta-download use the previously downloaded XML from GNOS, only useful for testing\n";

GetOptions("gnos-url=s" => \$gnos_url, "xml-file=s" => \$xml_file, "cluster-json=s" => \$cluster_json, "working-dir=s" => \$working_dir, "sample=s" => \$specific_sample, "test" => \$test, "ignore-lane-count" => \$ignore_lane_cnt, "force-run" => \$force_run, "threads=i" => \$threads, "skip-meta-download" => \$skip_down, "report=s" => \$report_name, "settings=s" => \$seqware_setting, "upload-results" => \$upload_results);

my $usage = "USAGE: $0 --xml-file <data.xml>";

die $usage unless $xml_file;

# capture the name of the centre from the command line using GetOpt::Long
# and use that string as a hash key to get the URL that you want
$gnos_url = $urls{$gnos_url};

if ($upload_results) { $skip_upload = "false"; }

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
open R, ">$report_name" or die;
# READ CLUSTER INFO AND RUNNING SAMPLES
# my ($cluster_info, $running_samples) = read_cluster_info($cluster_json);
my ($cluster_info, $running_samples);

# READ INFO FROM GNOS
my $sample_info = read_sample_info();

# SCHEDULE SAMPLES
# now look at each sample, see if it's already schedule, launch if not and a cluster is available, and then exit
schedule_samples($sample_info);

close $FH;
close R;

END {
    no integer;
    printf( STDERR "Running time: %5.2f minutes\n",((time - $^T) / 60));
} # close END block

###############
# SUBROUTINES #
###############

sub schedule_workflow {
  my ($d) = @_;
  my $workflow_accession = 0;
  my $host = "unknown";
  my $rand = substr(rand(), 2); 
  system("mkdir -p $working_dir/$rand");
  open OUT, ">$working_dir/$rand/workflow.ini" or die;
  print OUT "input_bam_paths=".join(",",sort(keys(%{$d->{local_bams}})))."\n";
  print OUT "gnos_input_file_urls=".$d->{gnos_input_file_urls}."\n";
  print OUT "gnos_input_metadata_urls=".$d->{analysis_url}."\n";
  print OUT "gnos_output_file_url=$gnos_url\n";
  print OUT "readGroup=\n";
  print OUT "numOfThreads=$threads\n";
  print OUT "skip_upload=$skip_upload\n";
  print OUT <<END;
#key=picardSortJobMem:type=integer:display=F:display_name=Memory for Picard merge, sort, index, and md5sum
picardSortJobMem=6
#key=picardSortMem:type=integer:display=F:display_name=Memory for Picard merge, sort, index, and md5sum
picardSortMem=4
#key=input_reference:type=text:display=F:display_name=The reference used for BWA
input_reference=\${workflow_bundle_dir}/Workflow_Bundle_BWA/2.1/data/reference/bwa-0.6.2/genome.fa.gz
#key=maxInsertSize:type=integer:display=F:display_name=The max insert size if known
maxInsertSize=
#key=bwaAlignMemG:type=integer:display=F:display_name=Memory for BWA align step
bwaAlignMemG=8
#key=output_prefix:type=text:display=F:display_name=The output_prefix is a convention and used to specify the root of the absolute output path or an S3 bucket name
output_prefix=./
#key=additionalPicardParams:type=text:display=F:display_name=Any additional parameters you want to pass to Picard
additionalPicardParams=
#key=bwaSampeMemG:type=integer:display=F:display_name=Memory for BWA sampe step
bwaSampeMemG=8
#key=bwaSampeSortSamMemG:type=integer:display=F:display_name=Memory for BWA sort sam step
bwaSampeSortSamMemG=4
#key=bwa_aln_params:type=text:display=F:display_name=Extra params for bwa aln
bwa_aln_params=
#key=gnos_key:type=text:display=T:display_name=The path to a GNOS key.pem file
gnos_key=\${workflow_bundle_dir}/Workflow_Bundle_BWA/2.1/scripts/gnostest.pem
#key=uploadScriptJobMem:type=integer:display=F:display_name=Memory for upload script
uploadScriptJobMem=2
#key=output_dir:type=text:display=F:display_name=The output directory is a conventions and used in many workflows to specify a relative output path
output_dir=seqware-results
#key=bwa_sampe_params:type=text:display=F:display_name=Extra params for bwa sampe
bwa_sampe_params=
# key=bwa_choice:type=pulldown:display=T:display_name=Choice to use bwa-aln or bwa-mem:pulldown_items=mem|mem;aln|aln
bwa_choice=mem
# key=bwa_mem_params:type=text:display=F:display_name=Extra params for bwa mem
bwa_mem_params=
END
  close OUT;
  my $settings = `cat $seqware_setting`;
  my $cluster_found = 0;
  my $url = "";
  foreach my $cluster (keys %{$cluster_info}) {
    $url = $cluster_info->{$cluster}{webservice}; 
    my $username = $cluster_info->{$cluster}{username}; 
    my $password = $cluster_info->{$cluster}{password}; 
    $workflow_accession = $cluster_info->{$cluster}{workflow_accession};
    $host = $cluster_info->{$cluster}{host};
    $settings =~ s/SW_REST_URL=.*/SW_REST_URL=$url/g;
    $settings =~ s/SW_REST_USER=.*/SW_REST_USER=$username/g;
    $settings =~ s/SW_REST_PASS=.*/SW_REST_PASS=$password/g;
    $cluster_found = 1;
    delete $cluster_info->{$cluster};
    last;
  }
  open OUT, ">$working_dir/$rand/settings" or die;
  print OUT $settings;
  close OUT;
  # now submit the workflow!
  my $dir = getcwd();
  my $cmd = "SEQWARE_SETTINGS=$working_dir/$rand/settings /usr/local/bin/seqware workflow schedule --accession $workflow_accession --host $host --ini $working_dir/$rand/workflow.ini";
  if (!$test && $cluster_found) {
    print R "\tLAUNCHING WORKFLOW: $working_dir/$rand/workflow.ini\n";
    print R "\t\tCLUSTER HOST: $host ACCESSION: $workflow_accession URL: $url\n";
    print R "\t\tLAUNCH CMD: $cmd\n";
    open S, ">temp_script.sh" or die;
    # FIXME: this is all extremely brittle when executed via cronjobs
    print S "#!/bin/bash

source ~/.bashrc

cd $dir
export SEQWARE_SETTINGS=$working_dir/$rand/settings
export PATH=\$PATH:/usr/local/bin
env
seqware workflow schedule --accession $workflow_accession --host $host --ini $working_dir/$rand/workflow.ini

";
    close S;
    if (system("bash -l $dir/temp_script.sh > submission.out 2> submission.err") != 0) {
      print R "\t\tSOMETHING WENT WRONG WITH SCHEDULING THE WORKFLOW\n";
    }
  } elsif (!$test && !$cluster_found) {
    print R "\tNOT LAUNCHING WORKFLOW, NO CLUSTER AVAILABLE: $working_dir/$rand/workflow.ini\n";
    print R "\t\tLAUNCH CMD WOULD HAVE BEEN: $cmd\n";
  } else {
    print R "\tNOT LAUNCHING WORKFLOW BECAUSE --test SPECIFIED: $working_dir/$rand/workflow.ini\n";
    print R "\t\tLAUNCH CMD WOULD HAVE BEEN: $cmd\n";
  }
  print R "\n";
}

sub schedule_samples {
    print R "SAMPLE SCHEDULING INFORMATION\n\n";
    my $rec_no = 0;
    die "\$sample_info hashref is empty!" unless ($sample_info);
    print $FH "project\tdonor\tspecimen\tsample\talignment\tdate\tnum_of_bams\taligned_bam\taliquot_id\tuse_control\n";
    foreach my $project (sort keys %{$sample_info}) {
        $rec_no++;
        if ( $project ) {
            print R "Now processing XML files for $project\n";
            print STDERR "Now processing XML files for $project\n";
        }
        else {
            print R "Record $rec_no: no ICGC-DCC PROJECT CODE found in GNOS XML files\n";
        }
        foreach my $donor ( keys %{$sample_info->{$project}} ) {
            # skip processing this the metadata (and omit the row from the table) 
            # if no donor name was extracted from the XML file
            next unless $donor;
            print R "DONOR: $donor\n";
            foreach my $specimen (keys %{$sample_info->{$project}{$donor}}) {
                my $d = {};
                $d->{gnos_url} = $gnos_url;
                my $aligns = {};
                if ( $specimen ) {
                    print R "  SAMPLE OVERVIEW\n";
                    print R "  SPECIMEN/SAMPLE: $specimen\n";
                }
                else {
                    print R "  Record $rec_no: no SPECIMEN or SAMPLE ID found in GNOS XML files\n\n";
                }

                foreach my $sample ( keys %{$sample_info->{$project}{$donor}{$specimen}} ) {
                    print R "    SAMPLE: $sample\n";
                    foreach my $alignment ( keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}} ) {
                        my $type = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{type};
                        my $aliquot_id = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{aliquot_id};
                        my $analysis_id = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{analysis_id};
                        # check for duplicated aligned bam files (different names but from the same donor_specimen_sample)

     	                if ( $alignment ) {
                            print R "    ALIGNMENT: $alignment\n";
                        }
                        else {
                            print R "    Record $rec_no: no ALIGNMENT found in GNOS XML files\n\n";
    	                }
                        $aligns->{$alignment} = 1;
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

            # analysis
            # foreach my $analysis (sort keys %{$sample_info->{$participant}{$sample}{$alignment}{$aliquot}{$library}{analysis_id}}) {
              # $d->{analysisURL}{"$gnos_url/cghub/metadata/analysisFull/$analysis"} = 1;
              # $d->{downloadURL}{"$gnos_url/cghub/data/analysis/download/$analysis"} = 1;
            # }
            # $d->{gnos_input_file_urls} = join (",", (sort keys %{$d->{downloadURL}}));
            # print R "          BAMS: ", join(",", (keys %{$sample_info->{$participant}{$sample}{$alignment}{$aliquot}{$library}{files}})), "\n";
            # print R "          ANALYSIS_IDS: ", join(",", (keys %{$sample_info->{$participant}{$sample}{$alignment}{$aliquot}{$library}{analysis_id}})), "\n\n";
          # }
                            # most of the analysis objects will not contain aligned bam files
                            my $aligned_bam = 'none';
                            # new method of storing the number of counts:
                            my $num_bam_files = $sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{bams_count};
                            # Test and see if there is only a single bam file
              	            if ( $num_bam_files == 1 and $alignment ne 'unaligned' ) {
                                ($aligned_bam) = keys %{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{files}};
			    }

                            my @dates = ();
  	                    if ( defined ($sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{date}) ) {
                                @dates = sort {$b <=> $a} @{$sample_info->{$project}{$donor}{$specimen}{$sample}{$alignment}{date}};
    	                    }
                            else {
                                @dates = ( '0000-00-00', );
                            }
                            my $date = $dates[0];
                            # print the first 8 columns
                            print $FH "$project\t$donor\t$specimen\t$sample\t$alignment\t$date\t$num_bam_files\t$aligned_bam\t$aliquot_id";
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

                        print R "  SAMPLE WORKLFOW ACTION OVERVIEW\n";
                        print R "    LANES SPECIFIED FOR SAMPLE: $d->{total_lanes}\n";
                        #print Dumper($d->{total_lanes_hash});
                        print R "    BAMS FOUND: $d->{bams_count}\n";
      #print Dumper($d->{bams});
                        my $veto = 0;
      # so, do I run this?
      # if ((scalar(keys %{$aligns}) == 1 && defined($aligns->{unaligned})) || $force_run) { print R "\t\tONLY UNALIGNED OR RUN FORCED!\n"; }
      # else { print R "\t\tCONTAINS ALIGNMENT!\n"; $veto = 1; }
      # now check if this is alreay scheduled
      # my $analysis_url_str = join(",", sort(keys(%{$d->{analysisURL}})));
      # $d->{analysis_url} = $analysis_url_str;
      # print "ANALYSISURL $analysis_url_str\n";
      # if (!defined($running_samples->{$analysis_url_str}) || $force_run) {
        # print R "\t\tNOT PREVIOUSLY SCHEDULED OR RUN FORCED!\n";
      # } else {
        # print R "\t\tIS PREVIOUSLY SCHEDULED, RUNNING, OR FAILED!\n";
        # print R "\t\t\tSTATUS: ".$running_samples->{$analysis_url_str}."\n";
        # $veto = 1; 
      # }
      # now check the number of bams == lane count (or this check is suppressed) 
                        if ($d->{total_lanes} == $d->{bams_count} || $ignore_lane_cnt || $force_run) {
                            print R "\t\tLANE COUNT MATCHES OR IGNORED OR RUN FORCED: $ignore_lane_cnt $d->{total_lanes} $d->{bams_count}\n";
                        } 
                        else {
                            print R "\t\tLANE COUNT MISMATCH!\n";
                            $veto=1;
                        }
                        if ($veto) { 
                            print R "\t\tWILL NOT SCHEDULE THIS SAMPLE FOR ALIGNMENT!\n"; 
                        }
                        else {
                            print R "\t\tSCHEDULING WORKFLOW FOR THIS SAMPLE!\n";
#        schedule_workflow($d);
                        }
                        # print R "%%\n\n";

		    } # close foreach my alignment
		} # close foreach my sample
	    } # close foreach my specimen
	} # close foreach my donor
    } # close foreach my project
} # close sub

sub read_sample_info {
  open OUT, ">xml_parse_" . $timestamp . ".log" or die;
  my $d = {};
  my $type = q{};

  # PARSE XML
  my $parser = new XML::DOM::Parser;

  # read in the xml file returned by the cgquery command
  # my $doc = $parser->parsefile("data.xml");
  my $doc = $parser->parsefile("$xml_file");
  
  # print OUT all HREF attributes of all CODEBASE elements
  my $nodes = $doc->getElementsByTagName ("Result");
  my $n = $nodes->getLength;

  # DEBUG
  #$n = 30;
  
  print OUT "\n";

  # iterate over the Result XML files that were downloaded into the 
  # xml/ directory  
  for (my $i = 0; $i < $n; $i++)
  {
      my $node = $nodes->item ($i);
      #$node->getElementsByTagName('analysis_full_uri')->item(0)->getAttributeNode('errors')->getFirstChild->getNodeValue;
      #print OUT $node->getElementsByTagName('analysis_full_uri')->item(0)->getFirstChild->getNodeValue;
      my $aurl = getVal($node, "analysis_full_uri"); # ->getElementsByTagName('analysis_full_uri')->item(0)->getFirstChild->getNodeValue;
      # have to ensure the UUID is lower case, known GNOS issue
      #print OUT "Analysis Full URL: $aurl\n";
      if($aurl =~ /^(.*)\/([^\/]+)$/) {
      $aurl = $1."/".lc($2);
      } else { 
        print OUT "SKIPPING!\n";
        next;
      }
      print OUT "ANALYSIS FULL URL: $aurl\n";
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
      my $analysis_id = getVal($adoc, 'analysis_id');
      my $mod_time = getVal($adoc, 'last_modified');
      my $analysisDataURI = getVal($adoc, 'analysis_data_uri');
      # $submitterAliquotId will contain whichever matches first
      # This is defunct (I believe)
      my $submitterAliquotId = getCustomVal($adoc2, 'submitter_aliquot_id,submitter_sample_id');
      # this gets changed below
      # my $specimen_id = getCustomVal($adoc2, 'submitter_sample_id');
      # my $aliquotId = getCustomVal($adoc2, 'aliquot_id');
      my $aliquot_id = getVal($adoc, 'aliquot_id');
      # $submitterParticipantId will contain whichever matches first
      # my $submitterParticipantId = getCustomVal($adoc2, 'submitter_participant_id,submitter_donor_id');
      # my $donor_id = getCustomVal($adoc2, 'participant_id,submitter_donor_id');
      my $donor_id = getCustomVal($adoc2, 'submitter_donor_id');
      # my $submitterSampleId = getCustomVal($adoc2, 'submitter_sample_id');
      my $specimen_id = getCustomVal($adoc2, 'submitter_specimen_id');
      my $sample_id = getCustomVal($adoc2, 'submitter_sample_id');
      # if donor_id defined then dealing with newer XML
      # if (defined(getCustomVal($adoc2, 'submitter_donor_id')) && getCustomVal($adoc2, 'submitter_donor_id') ne '') {
      #  $submitterSampleId = getCustomVal($adoc2, 'submitter_specimen_id');
      # }
      # $sampleId will contain whichever matches first
      # my $sampleId = getCustomVal($adoc2, 'sample_id,submitter_specimen_id');
      my $use_control = getCustomVal($adoc2, "use_cntl");
      my $alignment = getVal($adoc, "refassem_short_name");
      my $total_lanes = getCustomVal($adoc2, "total_lanes");
      my $sample_uuid = getXPathAttr($adoc2, "refname", "//ANALYSIS_SET/ANALYSIS/TARGETS/TARGET/\@refname");
      # print OUT "TIME STAMP:  $mod_time\n";      
      # print OUT "ANALYSIS:  $analysisDataURI\n";
      # print OUT "ANALYSISID: $analysisId\n";
      # print OUT "PARTICIPANT ID: $participantId\n";
      # print OUT "SAMPLE ID: $sampleId\n";
      # print OUT "ALIQUOTID: $aliquotId\n";
      # print OUT "SUBMITTER PARTICIPANT ID: $submitterParticipantId\n";
      # print OUT "SUBMITTER SAMPLE ID: $submitterSampleId\n";
      # print OUT "SUBMITTER ALIQUOTID: $submitterAliquotId\n";
      my $libName = getVal($adoc, 'LIBRARY_NAME');
      my $libStrategy = getVal($adoc, 'LIBRARY_STRATEGY');
      my $libSource = getVal($adoc, 'LIBRARY_SOURCE');
      # print OUT "LibName: $libName LibStrategy: $libStrategy LibSource: $libSource\n";
      # get files
      # now if these are defined then move onto the next step
      # $participantId = $participantId . '_' . $date;
      # if (defined($libName) && defined($libStrategy) && defined($libSource) && defined($analysisId) && defined($analysisDataURI)) { 
        # print OUT "  gtdownload -c gnostest.pem -v -d $analysisDataURI\n";
        #system "gtdownload -c gnostest.pem -vv -d $analysisId\n";
        # print OUT "\n";
        # in the data structure each Analysis Set is sorted by it's ICGC DCC project code, then the combination of
        # donor, specimen, and sample that should be unique identifiers
        # there should only be to different types of alignment. For aligned samples there should be a single 
        # modification date, for the unaligned, each bam file will have a slightly different one, so
        # we will take the most recent one (sort the array later)
        # print "Contents of \$aliquot_id:\t$aliquot_id\n";
        # print "Contents of \$sample_uuid:\t$sample_uuid\n";
        # print "Contents of \$use_control:\t$use_control\n";
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
      print OUT "FILE:\n";
      foreach my $file(keys %{$files}) {
        next if $file =~ m/\.bai/;
        print OUT "  FILE: $file SIZE: " . $files->{$file}{size} . " CHECKSUM: " . $files->{$file}{checksum} . "\n";
        # print OUT "  LOCAL FILE PATH: $analysisId/$file\n";
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{files}{$file}{size} = $files->{$file}{size}; 
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{files}{$file}{checksum} = $files->{$file}{checksum}; 
        $d->{$project}{$donor_id}{$specimen_id}{$sample_id}{$alignment}{files}{$file}{localpath} = "$file"; 
        # URLs?
      }
#      print Data::Dumper->new([\$files],[qw(files)])->Indent(1)->Quotekeys(0)->Dump, "\n";
  }
print Data::Dumper->new([\$d],[qw(d)])->Indent(1)->Quotekeys(0)->Dump, "\n";
exit;

  # Print doc file
  #$doc->printToFile ("out.xml");
  # Print to string
  #print OUT $doc->toString;
  # Avoid memory leaks - cleanup circular references for garbage collection
  $doc->dispose;
  close OUT;
  return($d);
}

sub read_cluster_info {
  my ($cluster_info) = @_;
  my $json_txt = "";
  my $d = {};
  my $run_samples = {};
  if ($cluster_info ne "" && -e $cluster_info) {
    open IN, "<$cluster_info" or die "Can't open $cluster_info";
    while(<IN>) {
      $json_txt .= $_;
    }
    close IN; 
    my $json = decode_json($json_txt);
  
    foreach my $c (keys %{$json}) {
      my $user = $json->{$c}{username};
      my $pass = $json->{$c}{password};
      my $web = $json->{$c}{webservice};
      my $acc = $json->{$c}{workflow_accession};
      print R "EXAMINING CLUSER: $c\n";
      #print "wget -O - --http-user=$user --http-password=$pass -q $web\n"; 
      my $info = `wget -O - --http-user='$user' --http-password=$pass -q $web/workflows/$acc`; 
      #print "INFO: $info\n";
      my $dom = XML::LibXML->new->parse_string($info);
      # check the XML returned above
      if ($dom->findnodes('//Workflow/name/text()')) {
        # now figure out if any of these workflows are currently scheduled here
        #print "wget -O - --http-user='$user' --http-password=$pass -q $web/workflows/$acc/runs\n";
        my $wr = `wget -O - --http-user='$user' --http-password=$pass -q $web/workflows/$acc/runs`; 
        #print "WR: $wr\n";
        my $dom2 = XML::LibXML->new->parse_string($wr);
  
        # find available clusters
        my $running = 0;
        print R "\tWORKFLOWS ON THIS CLUSTER\n";
        my $i=0;
        for my $node ($dom2->findnodes('//WorkflowRunList2/list/status/text()')) {
          $i++;
          print R "\t\tWORKFLOW: ".$acc." STATUS: ".$node->toString()."\n";
          if ($node->toString() eq 'running' || $node->toString() eq 'scheduled' || $node->toString() eq 'submitted') { $running++; }
          # find running samples
          my $j=0;
          for my $node2 ($dom2->findnodes('//WorkflowRunList2/list/iniFile/text()')) {
            $j++;
            my $ini_contents = $node2->toString();
            $ini_contents =~ /gnos_input_metadata_urls=(\S+)/;
            my @urls = split /,/, $1;
            my $sorted_urls = join(",", sort @urls);
            if ($i==$j) { $run_samples->{$sorted_urls} = $node->toString(); print R "\t\t\tINPUTS: $sorted_urls\n"; }
          }
          $j=0;
          for my $node2 ($dom2->findnodes('//WorkflowRunList2/list/currentWorkingDir/text()')) {
            $j++;
            if ($i==$j) { my $txt = $node2->toString(); print R "\t\t\tCWD: $txt\n"; }
          }
          $j=0;
          for my $node2 ($dom2->findnodes('//WorkflowRunList2/list/swAccession/text()')) {
            $j++;
            if ($i==$j) { my $txt = $node2->toString(); print R "\t\t\tWORKFLOW ACCESSION: $txt\n"; }
          }
        } 
        # if there are no running workflows on this cluster it's a candidate
        if ($running == 0) {
          print R "\tNO RUNNING WORKFLOWS, ADDING TO LIST OF AVAILABLE CLUSTERS\n\n";
          $d->{$c} = $json->{$c}; 
        } else {
          print R "\tCLUSTER HAS RUNNING WORKFLOWS, NOT ADDING TO AVAILABLE CLUSTERS\n\n";
        }
      }
    }
  }
  #print "Final cluster list:\n";
  #print Dumper($d);
  return($d, $run_samples);
  
}

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
}

sub getCustomVal {
#  print $FH "getCustomVal:\n";
  my ($dom2, $keys) = @_;
  my @keys_arr = split /,/, $keys;
  for my $node ($dom2->findnodes('//ANALYSIS_ATTRIBUTES/ANALYSIS_ATTRIBUTE')) {
    my $i=0;
    for my $currKey ($node->findnodes('//TAG/text()')) {
      $i++;
      my $keyStr = $currKey->toString();
#      print $FH "\$keyStr contains: $keyStr\n";
      foreach my $key (@keys_arr) {
#        print $FH "\t\$key contains: $key\n";
        if ($keyStr eq $key) {
          my $j=0;
          for my $currVal ($node->findnodes('//VALUE/text()')) {
#            print $FH "\t\t\$currVal contains:", $currVal->toString(), "\n";
            $j++;   
            if ($j==$i) { 
#              print $FH "\t\t\tselected \$currVal contains:", $currVal->toString(), "\n";
              return($currVal->toString());
            }
          } 
        }
      }
    }
  }
  return("");
}

sub getXPathAttr {
  my ($dom, $key, $xpath) = @_;
  #print "HERE $dom $key $xpath\n";
  for my $node ($dom->findnodes($xpath)) {
    #print "NODE: ".$node->getValue()."\n";
    return($node->getValue());
  }
  return "";
}

sub getVal {
  my ($node, $key) = @_;
  #print "NODE: $node KEY: $key\n";
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
}

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
}

__END__

