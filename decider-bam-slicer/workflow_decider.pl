use strict;
use XML::DOM;
use Data::Dumper;
use JSON;
use Getopt::Long;
use XML::LibXML;
use Cwd;

# DESCRIPTION
# A tool for identifying samples ready for alignment, scheduling on clusters,
# and monitoring for completion.
# TODO:
# * need to use perl package for downloads, not calls out to system
# * need to define cluster json so this script knows how to launch a workflow

#############
# VARIABLES #
#############

my $skip_down = 0;
my $gnos_url = "https://gtrepo-ebi.annailabs.com";
my $cluster_json = "";
my $working_dir = "decider_tmp";
my $specific_sample; # submitter specimen ID
my $aliquot_list_file;
my $test = 0;
my $ignore_lane_cnt = 0;
my $force_run = 0;
my $threads = 8;
my $report_name = "workflow_decider_report.txt";
my $seqware_setting = "seqware.setting";
# by default skip the upload of results back to GNOS
my $skip_upload = "true";
my $use_gtdownload = "true";
my $use_gtupload = "true";
my $upload_results = 0;
my $ignore_failed = 0;
my $skip_cached = 0;
my $skip_gtdownload = 0;
my $skip_gtupload = 0;
my $output_prefix = "./";
my $output_dir = "seqware-results/";
my $input_prefix = "";

if (scalar(@ARGV) < 4 || scalar(@ARGV) > 28) {
  print "USAGE: 'perl $0 --gnos-url <URL> --cluster-json <cluster.json> [--working-dir <working_dir>] [--sample <sample_id>] [--aliquot-list-file <aliquot_list_file>] [--threads <num_threads_bwa_default_8>] [--test] [--ignore-lane-count] [--force-run] [--skip-meta-download] [--report <workflow_decider_report.txt>] [--settings <seqware_settings_file>] [--upload-results] [--skip-cached]'\n";
  print "\t--gnos-url           a URL for a GNOS server, e.g. https://gtrepo-ebi.annailabs.com\n";
  print "\t--cluster-json       a json file that describes the clusters available to schedule workflows to\n";
  print "\t--working-dir        a place for temporary ini and settings files\n";
  print "\t--sample             to only run a particular sample\n";
  print "\t--aliquot_list_file  to only run particular aliquots in a file listing aliquot_ids\n";
  print "\t--threads            number of threads to use for BWA\n";
  print "\t--test               a flag that indicates no workflow should be scheduled, just summary of what would have been run\n";
  print "\t--ignore-lane-count  skip the check that the GNOS XML contains a count of lanes for this sample and the bams count matches\n";
  print "\t--force-run          schedule workflows even if they were previously completed/failed/scheduled\n";
  print "\t--skip-meta-download use the previously downloaded XML from GNOS, only useful for testing\n";
  print "\t--report             the report file name\n";
  print "\t--settings           the template seqware settings file\n";
  print "\t--upload-results     a flag indicating the resulting BAM files and metadata should be uploaded to GNOS, default is to not upload!!!\n";
  print "\t--ignore-failed      a flag indicating that previously failed runs for this specimen should be ignored and the specimen scheduled again\n";
  print "\t--skip-cached        a flag indicating that previously download metadata XML files should not be downloaded again\n";
  print "\t--skip-gtdownload    a flag indicating that input files should be just the bam input paths and not from GNOS\n";
  print "\t--skip-gtupload      a flag indicating that upload should not take place but output files should be placed in output_prefix/output_dir\n";
  print "\t--output-prefix      if --skip-gtupload is set, use this to specify the prefix of where output files are written\n";
  print "\t--output-dir         if --skip-gtupload is set, use this to specify the dir of where output files are written\n";
  print "\t--input-prefix       if --skip-gtdownload is set, this is the input bam file prefix\n";
  exit(1);
}

GetOptions("gnos-url=s" => \$gnos_url, "cluster-json=s" => \$cluster_json, "working-dir=s" => \$working_dir, "sample=s" => \$specific_sample, "aliquot-list-file=s" => \$aliquot_list_file, "test" => \$test, "ignore-lane-count" => \$ignore_lane_cnt, "force-run" => \$force_run, "threads=i" => \$threads, "skip-meta-download" => \$skip_down, "report=s" => \$report_name, "settings=s" => \$seqware_setting, "upload-results" => \$upload_results, "ignore-failed" => \$ignore_failed, "skip-cached" => \$skip_cached, "skip-gtdownload" => \$skip_gtdownload, "skip-gtupload" => \$skip_gtupload, "output-prefix=s" => \$output_prefix, "output-dir=s" => \$output_dir, "input-prefix=s" => \$input_prefix);

if ($upload_results) { $skip_upload = "false"; }
if ($skip_gtdownload) { $use_gtdownload = "false"; }
if ($skip_gtupload) { $use_gtupload = "false"; }

my %aliquots;
if (-s $aliquot_list_file) { # if file exist and has size > 0
  open (A, "< $aliquot_list_file") || die "Unable to open file: $aliquot_list_file\n";
  while(<A>){
    s/\r\n//g;
    $aliquots{$_}++;
  }
  close(A);
}


##############
# MAIN STEPS #
##############

# output report file
open R, ">$report_name" or die;

# READ CLUSTER INFO AND RUNNING SAMPLES
my ($cluster_info, $running_samples) = read_cluster_info($cluster_json);
#print Dumper($cluster_info);
#print Dumper($running_samples);

# READ INFO FROM GNOS
my $sample_info = read_sample_info();
#print Dumper($sample_info);

# SCHEDULE SAMPLES
# now look at each sample, see if it's already schedule, launch if not and a cluster is available, and then exit
schedule_samples($sample_info);

close R;

###############
# SUBROUTINES #
###############

# these params are need minimally
# input_bam_paths=9c414428-9446-11e3-86c1-ab5c73f0e08b/hg19.chr22.5x.normal.bam
# gnos_input_file_urls=https://gtrepo-ebi.annailabs.com/cghub/data/analysis/download/9c414428-9446-11e3-86c1-ab5c73f0e08b
# gnos_input_metadata_urls=https://gtrepo-ebi.annailabs.com/cghub/metadata/analysisFull/9c414428-9446-11e3-86c1-ab5c73f0e08b
# gnos_output_file_url=https://gtrepo-ebi.annailabs.com
# readGroup=
# numOfThreads=1
sub schedule_workflow {
  my ($d) = @_;
  #print Dumper($cluster_info);
  #print Dumper($d);

  my $rand = substr(rand(), 2);
  my $host = "unknown";
  my $workflow_accession = 0;
  my $workflow_version = "0.1.0";
  # parse cluster info
  my $settings = `cat $seqware_setting`;
  my $cluster_found = 0;
  # cluster info
  my $url = "";
  foreach my $cluster (keys %{$cluster_info}) {
    $url = $cluster_info->{$cluster}{webservice};
    my $username = $cluster_info->{$cluster}{username};
    my $password = $cluster_info->{$cluster}{password};
    $workflow_accession = $cluster_info->{$cluster}{workflow_accession};
    $workflow_version = $cluster_info->{$cluster}{workflow_version};
    $host = $cluster_info->{$cluster}{host};
    $settings =~ s/SW_REST_URL=.*/SW_REST_URL=$url/g;
    $settings =~ s/SW_REST_USER=.*/SW_REST_USER=$username/g;
    $settings =~ s/SW_REST_PASS=.*/SW_REST_PASS=$password/g;
    # can only assign one workflow here per cluster
    $cluster_found = 1;
    delete $cluster_info->{$cluster};
    last;
  }
  system("mkdir -p $working_dir/$rand");
  open OUT, ">$working_dir/$rand/settings" or die "Can't open file $working_dir/$rand/settings\n";
  print OUT $settings;
  close OUT;

  # ini file
  open OUT, ">$working_dir/$rand/workflow.ini" or die;
  print OUT "input_bam_paths=".$d->{input_bam_paths}."\n";
  print OUT "gnos_input_file_urls=".$d->{gnos_input_file_urls}."\n";
  my $gnos_input_metadata_urls = $d->{gnos_input_file_urls};
  $gnos_input_metadata_urls =~ s|data/analysis/download|metadata/analysisFull|;
  print OUT "gnos_input_metadata_urls=$gnos_input_metadata_urls\n";
  print OUT <<END;
isTesting=false
testBamPath=\${workflow_bundle_dir}/Workflow_Bundle_BAM_Slicer/$workflow_version/data/sliceTest.bam
extract_and_upload_unmapped_reads=true
job_description_encode=BAM slice: ENCODE target regions. This BAM file contains reads in ENCODE pilot target regions (about 1 percent of the human genome) extracted from specimen-level aligned BAM file. The genome coordinates for these regions were downloaded using UCSC Table Browser using parameters: org is Human, db is hg19, hgta_track is encodeRegions, hgta_table is encodeRegions
job_description_unmapped=BAM slice: unmapped reads. This BAM file contains reads failed to map to the reference genome by BWA MEM aligner. These include mate-pairs with either one end or both ends unmapped.
use_gtdownload=true
use_gtupload=true
skip_upload=false
gnos_key=\${workflow_bundle_dir}/Workflow_Bundle_BAM_Slicer/$workflow_version/scripts/gnostest.pem
gnos_output_file_url=https://gtrepo-ebi.annailabs.com
output_dir=results/
output_prefix=./
gtdownloadRetries=30
gtdownloadMd5time=120
gtdownloadMemG=8
gtuploadMemG=8
smallJobMemM=2000
mergeJobMemG=8
numOfThreads=8
END
  close OUT;
  # now submit the workflow!
  my $dir = getcwd();
  my $cmd = "SEQWARE_SETTINGS=$working_dir/$rand/settings seqware workflow schedule --accession $workflow_accession --host $host --ini $working_dir/$rand/workflow.ini";
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
  my $my_sample_info = shift;

  print R "SAMPLE SCHEDULING INFORMATION\n\n";

  foreach my $project (keys %{$my_sample_info}) {
    my $sample_info = $my_sample_info->{$project};
    print R "PROJECT: $project\n\n";

    foreach my $participant (keys %{$sample_info}) {
      print R "DONOR/PARTICIPANT: $participant\n\n";
      foreach my $specimen (keys %{$sample_info->{$participant}}) {

        print R "\tSAMPLE OVERVIEW\n";
        print R "\tSPECIMEN: $specimen\n";
        foreach my $aliquot (keys %{$sample_info->{$participant}{$specimen}}) {
          print R "\t\tALIQUOT: $aliquot\n";

          # storing some info
          my $d = {};

          if (defined $sample_info->{$participant}{$specimen}{$aliquot}{description}{"BWA aligned"}
              && ( $force_run # forced to run
                   || !exists $sample_info->{$participant}{$specimen}{$aliquot}{description}{"ENCODE reads"} 
                   || !exists $sample_info->{$participant}{$specimen}{$aliquot}{description}{"Unmapped reads"} )) { # has BWA aligned BAM but missing extracted ones

            print R "\t\tCandidate BAM to be scheduled".($force_run ? " (forced)" : "").": ", $sample_info->{$participant}{$specimen}{$aliquot}{description}{"BWA aligned"}->[0]->[2], "\n";
            $d->{gnos_input_file_urls} = $sample_info->{$participant}{$specimen}{$aliquot}{description}{"BWA aligned"}->[0]->[1];
            $d->{input_bam_paths} = $sample_info->{$participant}{$specimen}{$aliquot}{description}{"BWA aligned"}->[0]->[2];

            if (!defined($running_samples->{ $d->{gnos_input_file_urls} }) || $force_run) {
              print R "\t\tNOT PREVIOUSLY SCHEDULED OR RUN FORCED!\n";
              schedule_workflow($d);
      
            } elsif ($running_samples->{ $d->{gnos_input_file_urls} } eq "failed" && $ignore_failed) {
              print R "\t\tPREVIOUSLY FAILED BUT RUN FORCED VIA IGNORE FAILED OPTION!\n";
              schedule_workflow($d);
      
            } else {
              print R "\t\tIS PREVIOUSLY SCHEDULED, RUNNING, OR FAILED!\n";
              print R "\t\t\tSTATUS: ".$running_samples->{ $d->{gnos_input_file_urls} }."\n";
      
            }

          } elsif (defined $sample_info->{$participant}{$specimen}{$aliquot}{description}{"BWA aligned"}) { # already done

            print R "\t\tENCODE and unmapped reads extraction already done: ", $sample_info->{$participant}{$specimen}{$aliquot}{description}{"BWA aligned"}->[0]->[0], "\n";

          } else { # no BWA aligned Sample level BAM, skip
            print R "\t\tCould not find aligned sample level BAM for this aliquot: $aliquot. Skip!\n";

          }
        }
      }
    }

  }
}

sub read_sample_info {

  system("mkdir -p $working_dir");
  open OUT, ">$working_dir/xml_parse.log" or die;
  my $d = {};

  # PARSE XML
  my $parser = new XML::DOM::Parser;
  #my $doc = $parser->parsefile ("https://cghub.ucsc.edu/cghub/metadata/analysisDetail?participant_id=3f70c3e3-0131-466f-92aa-0a63ab3d4258");
  #system("lwp-download 'https://cghub.ucsc.edu/cghub/metadata/analysisDetail?study=TCGA_MUT_BENCHMARK_4&state=live' data.xml");
  #my $doc = $parser->parsefile ('https://cghub.ucsc.edu/cghub/metadata/analysisDetail?study=TCGA_MUT_BENCHMARK_4&state=live');
  #if (!$skip_down) { my $cmd = "mkdir -p xml; cgquery -s $gnos_url --all-states -o xml/data.xml 'study=*'"; print OUT "$cmd\n"; system($cmd); }
  # cgquery -o my_data.xml 'study=PAWG&state=live'
  if (!$skip_down) {
    my $cmd = "mkdir -p $working_dir/xml; cgquery -s $gnos_url -o $working_dir/xml/data.xml 'study=*&state=live'";
    if ($gnos_url =~ /cghub.ucsc.edu/) {
      $cmd = "mkdir -p $working_dir/xml; cgquery -s $gnos_url -o $working_dir/xml/data.xml 'study=PAWG&state=live'";
    }
    print OUT "$cmd\n";
    my $rsult = system($cmd);
    if ($rsult) { print STDERR "Could not download data via cgquery!\n"; exit (1); }
  }
  my $doc = $parser->parsefile("$working_dir/xml/data.xml");

  # print OUT all HREF attributes of all CODEBASE elements
  my $nodes = $doc->getElementsByTagName ("Result");
  my $n = $nodes->getLength;

  # DEBUG
  #$n = 30;

  print OUT "\n";

  for (my $i = 0; $i < $n; $i++)
  {
      my $node = $nodes->item ($i);

      my $alignment = getVal($node, "refassem_short_name");
      next if ($alignment eq 'unaligned'); # skip download/process this if it's unaligned

      #$node->getElementsByTagName('analysis_full_uri')->item(0)->getAttributeNode('errors')->getFirstChild->getNodeValue;
      #print OUT $node->getElementsByTagName('analysis_full_uri')->item(0)->getFirstChild->getNodeValue;
      my $aurl = getVal($node, "analysis_full_uri"); # ->getElementsByTagName('analysis_full_uri')->item(0)->getFirstChild->getNodeValue;

      # have to ensure the UUID is lower case, known GNOS issue
      #print OUT "Analysis Full URL: $aurl\n";
      my $analysis_uuid = $i;
      if($aurl =~ /^(.*)\/([^\/]+)$/) {
        $aurl = $1."/".lc($2);
        $analysis_uuid = lc($2);
      } else {
        print OUT "SKIPPING!\n";
        next;
      }
      print OUT "\n";
      print OUT "ANALYSIS FULL URL: $aurl $analysis_uuid\n";

      if (!$skip_down) { download($aurl, "$working_dir/xml/data_$analysis_uuid.xml", $skip_cached); }

      my $adoc = $parser->parsefile ("$working_dir/xml/data_$analysis_uuid.xml");
      my $adoc2 = XML::LibXML->new->parse_file("$working_dir/xml/data_$analysis_uuid.xml");

      my $aliquotId = getVal($adoc, 'aliquot_id');
      if (keys %aliquots && !$aliquots{$aliquotId}){ # skip if aliquot_id list file specified and the current one is not included in the list
        print OUT "Skip as the aliquot ID is not in the list if specified aliquots\n";
        next;
      };

      my $description = getVal($adoc, 'DESCRIPTION');
      if ($description =~ /^Specimen-level BAM from the reference alignment/) {
         $description = "BWA aligned";
      }elsif ($description =~ /^BAM slice: ENCODE target regions/) {
         $description = "ENCODE reads";
      }elsif ($description =~ /^BAM slice: unmapped reads/) {
         $description = "Unmapped reads";
      }else{
         print OUT "SKIPPING! Unrelated AO: $description\n";
         next; # ignore if it's none of this
      }
      
      my $analysisId = getVal($adoc, 'analysis_id');
      my $analysisDataURI = getVal($adoc, 'analysis_data_uri');

      my $project_code = getCustomVal($adoc2, 'dcc_project_code');
      my $participantId = getCustomVal($adoc2, 'submitter_donor_id');
      my $submitterSpecimenId = getCustomVal($adoc2, 'submitter_specimen_id');
      my $submitterSampleId = getCustomVal($adoc2, 'submitter_sample_id');

      print OUT "ANALYSIS:  $analysisDataURI \n";
      print OUT "ANALYSISID: $analysisId\n";
      print OUT "PROJECT: $project_code\n";
      print OUT "PARTICIPANT ID: $participantId\n";
      print OUT "SUBMITTER SPECIMEN ID: $submitterSpecimenId\n";
      print OUT "SUBMITTER SAMPLE ID: $submitterSampleId\n";
      print OUT "ALIQUOTID: $aliquotId\n";
      print OUT "DESCRIPTION: $description\n";

      # get files
      my $files = &readFiles($adoc);
      if (0 + keys %{$files} > 1) {
        print OUT "ERROR: one GNOS Ananlysis Object expects only one BAM file, will skip $analysisId\n\n";
        next;
      }

      my $bam_file;
      print OUT "FILE:\n";
      foreach my $file(keys %{$files}) {
        print OUT "  FILE: $file SIZE: ".$files->{$file}{size}." CHECKSUM: ".$files->{$file}{checksum}."\n";
        print OUT "  LOCAL FILE PATH: $analysisId/$file\n";
        $bam_file = "$analysisId/$file";
      }

      # now if these are defined then move onto the next step
      if (defined $analysisId && defined $analysisDataURI && defined $bam_file) {
        if ($description eq "BWA aligned" && exists $d->{$project_code}{$participantId}{$submitterSpecimenId}{$aliquotId}{description}{$description}) {
          print OUT "ERROR: more than one BWA aligned BAM found for aliquot_id: $aliquotId, will skip this GNOS analysis_id $analysisId\n";
          next;
        }

        push @{ $d->{$project_code}{$participantId}{$submitterSpecimenId}{$aliquotId}{description}{$description} }, [$analysisId, $analysisDataURI, $bam_file];
      } else {
        print OUT "ERROR: one or more critical fields not defined, will skip $analysisId\n\n";
        next;
      }

  }

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
      my $max_running = $json->{$c}{max_workflows};
      my $max_scheduled_workflows = $json->{$c}{max_scheduled_workflows};
      if ($max_running <= 0 || $max_running eq "") { $max_running = 1; }
      if ($max_scheduled_workflows <= 0 || $max_scheduled_workflows eq "" || $max_scheduled_workflows > $max_running) { $max_scheduled_workflows = $max_running; }
      print R "EXAMINING CLUSER: $c\n";
      print "wget --timeout=60 -t 2 -O - --http-user=$user --http-password=$pass -q $web/workflows/$acc\n";
      my $info = `wget --timeout=60 -t 2 -O - --http-user='$user' --http-password=$pass -q $web/workflows/$acc`;
      #print "INFO: $info\n";
      if ($info ne "") {
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
            if ($node->toString() eq 'pending' || $node->toString() eq 'running' || $node->toString() eq 'scheduled' || $node->toString() eq 'submitted') { $running++; }
            # find running samples
            my $j=0;
            for my $node2 ($dom2->findnodes('//WorkflowRunList2/list/iniFile/text()')) {
              $j++;
              my $ini_contents = $node2->toString();
              $ini_contents =~ /gnos_input_file_urls=(\S+)/;
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
          if ($running < $max_running ) {
            print R "\tTHERE ARE $running RUNNING WORKFLOWS WHICH IS LESS THAN MAX OF $max_running, ADDING TO LIST OF AVAILABLE CLUSTERS\n\n";
            for (my $i=0; $i<$max_scheduled_workflows; $i++) {
              $d->{"$c\_$i"} = $json->{$c};
            }
          } else {
            print R "\tCLUSTER HAS RUNNING WORKFLOWS, NOT ADDING TO AVAILABLE CLUSTERS\n\n";
          }
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
  for (my $i = 0; $i < $n; $i++) {
    my $node = $nodes->item ($i);
    my $currFile = getVal($node, 'filename');
    next unless ($currFile =~ /\.bam$/); # only deal with BAM files

    my $size = getVal($node, 'filesize');
    my $check = getVal($node, 'checksum');
    $ret->{$currFile}{size} = $size;
    $ret->{$currFile}{checksum} = $check;
  }
  return($ret);
}

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
  my ($url, $out, $skip) = @_;

  if (!-e $out || !$skip) {
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
}
