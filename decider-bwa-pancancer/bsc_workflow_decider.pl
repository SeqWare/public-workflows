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
my $gnos_url = "https://gtrepo-bsc.annailabs.com";
my $cluster_json = "";
my $working_dir = "decider_tmp";
my $specific_sample;
my $test = 0;
my $ignore_lane_cnt = 0;
my $force_run = 0;
my $threads = 8;
my $report_name = "workflow_decider_report.txt";
my $seqware_setting = "seqware.setting";
# by default skip the upload of results back to GNOS
my $skip_upload = "true";
my $upload_results = 0;
my $ignore_failed = 0;

if (scalar(@ARGV) < 6 || scalar(@ARGV) > 20) {
  print "USAGE: 'perl $0 --gnos-url <URL> --cluster-json <cluster.json> [--working-dir <working_dir>] [--sample <sample_id>] [--threads <num_threads_bwa_default_8>] [--test] [--ignore-lane-count] [--force-run] [--skip-meta-download] [--report <workflow_decider_report.txt>] [--settings <seqware_settings_file>] [--upload-results]'\n";
  print "\t--gnos-url           a URL for a GNOS server, e.g. https://gtrepo-ebi.annailabs.com\n";
  print "\t--cluster-json       a json file that describes the clusters available to schedule workflows to\n";
  print "\t--working-dir        a place for temporary ini and settings files\n";
  print "\t--sample             to only run a particular sample\n";
  print "\t--threads            number of threads to use for BWA\n";
  print "\t--test               a flag that indicates no workflow should be scheduled, just summary of what would have been run\n";
  print "\t--ignore-lane-count  skip the check that the GNOS XML contains a count of lanes for this sample and the bams count matches\n";
  print "\t--force-run          schedule workflows even if they were previously run/failed/scheduled\n";
  print "\t--skip-meta-download use the previously downloaded XML from GNOS, only useful for testing\n";
  print "\t--report             the report file name\n";
  print "\t--settings           the template seqware settings file\n";
  print "\t--upload-results     a flag indicating the resulting BAM files and metadata should be uploaded to GNOS, default is to not upload!!!\n";
  print "\t--ignore-failed      a flag indicating that previously failed runs for this specimen should be ignored and the specimen scheduled again\n";
  exit;
}

GetOptions("gnos-url=s" => \$gnos_url, "cluster-json=s" => \$cluster_json, "working-dir=s" => \$working_dir, "sample=s" => \$specific_sample, "test" => \$test, "ignore-lane-count" => \$ignore_lane_cnt, "force-run" => \$force_run, "threads=i" => \$threads, "skip-meta-download" => \$skip_down, "report=s" => \$report_name, "settings=s" => \$seqware_setting, "upload-results" => \$upload_results, "ignore-failed" => \$ignore_failed);

if ($upload_results) { $skip_upload = "false"; }


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
  my $workflow_version = "2.4.0";
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
  open OUT, ">$working_dir/$rand/settings" or die;
  print OUT $settings;
  close OUT;

  # ini file
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
input_reference=\${workflow_bundle_dir}/Workflow_Bundle_BWA/$workflow_version/data/reference/bwa-0.6.2/genome.fa.gz
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
gnos_key=\${workflow_bundle_dir}/Workflow_Bundle_BWA/$workflow_version/scripts/gnostest.pem
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
# GTDownload
# key=gtdownload_retries:type=integer:display=F:display_name=How many retries to attempt before restarting gtdownload, each lasts 1 minute
gtdownload_retries=120
END
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
  foreach my $participant (keys %{$sample_info}) {
    print R "DONOR/PARTICIPANT: $participant\n\n";
    foreach my $sample (keys %{$sample_info->{$participant}}) {
      if (defined($specific_sample) && $specific_sample ne '' && $specific_sample ne $sample) { next; }
      # storing some info
      my $d = {};
      $d->{gnos_url} = $gnos_url;
      my $aligns = {};
      print R "\tSAMPLE OVERVIEW\n";
      print R "\tSPECIMEN/SAMPLE: $sample\n";
      foreach my $alignment (keys %{$sample_info->{$participant}{$sample}}) {
        print R "\t\tALIGNMENT: $alignment\n";
        $aligns->{$alignment} = 1;
        foreach my $aliquot (keys %{$sample_info->{$participant}{$sample}{$alignment}}) {
          print R "\t\t\tANALYZED SAMPLE/ALIQUOT: $aliquot\n";
          foreach my $library (keys %{$sample_info->{$participant}{$sample}{$alignment}{$aliquot}}) {
            print R "\t\t\t\tLIBRARY: $library\n";
            #print "$participant\t$sample\t$alignment\t$aliquot\t$library\n";
            # read lane counts
            my $total_lanes = 0;
            foreach my $lane (keys %{$sample_info->{$participant}{$sample}{$alignment}{$aliquot}{$library}{total_lanes}}) {
              if ($lane > $total_lanes) { $total_lanes = $lane; }
            }
            $d->{total_lanes_hash}{$total_lanes} = 1;
            $d->{total_lanes} = $total_lanes;
            foreach my $bam (keys %{$sample_info->{$participant}{$sample}{$alignment}{$aliquot}{$library}{files}}) {
              $d->{bams}{$bam} = $sample_info->{$participant}{$sample}{$alignment}{$aliquot}{$library}{files}{$bam}{localpath};
              $d->{local_bams}{$sample_info->{$participant}{$sample}{$alignment}{$aliquot}{$library}{files}{$bam}{localpath}} = 1;
              if ($alignment eq "unaligned") {
                $d->{bams_count}++;
              }
            }
            # analysis
            foreach my $analysis (sort keys %{$sample_info->{$participant}{$sample}{$alignment}{$aliquot}{$library}{analysis_id}}) {
              $d->{analysisURL}{"$gnos_url/cghub/metadata/analysisFull/$analysis"} = 1;
              $d->{downloadURL}{"$gnos_url/cghub/data/analysis/download/$analysis"} = 1;
            }
            $d->{gnos_input_file_urls} = join (",", (sort keys %{$d->{downloadURL}}));
            print R "\t\t\t\t\tBAMS: ", join(",", (keys %{$sample_info->{$participant}{$sample}{$alignment}{$aliquot}{$library}{files}})), "\n";
            print R "\t\t\t\t\tANALYSIS_IDS: ", join(",", (keys %{$sample_info->{$participant}{$sample}{$alignment}{$aliquot}{$library}{analysis_id}})), "\n\n";
          }
        }
      }
      print R "\tSAMPLE WORKLFOW ACTION OVERVIEW\n";
      print R "\t\tLANES SPECIFIED FOR SAMPLE: $d->{total_lanes}\n";
      #print Dumper($d->{total_lanes_hash});
      print R "\t\tBAMS FOUND: $d->{bams_count}\n";
      #print Dumper($d->{bams});
      my $veto = 0;
      # so, do I run this?
      if ((scalar(keys %{$aligns}) == 1 && defined($aligns->{unaligned})) || $force_run) { print R "\t\tONLY UNALIGNED OR RUN FORCED!\n"; }
      else { print R "\t\tCONTAINS ALIGNMENT!\n"; $veto = 1; }
      # now check if this is alreay scheduled
      my $analysis_url_str = join(",", sort(keys(%{$d->{analysisURL}})));
      $d->{analysis_url} = $analysis_url_str;
      #print "ANALYSISURL $analysis_url_str\n";
      if (!defined($running_samples->{$analysis_url_str}) || $force_run) {
        print R "\t\tNOT PREVIOUSLY SCHEDULED OR RUN FORCED!\n";
      } elsif ($running_samples->{$analysis_url_str} eq "failed" && $ignore_failed) {
        print R "\t\tPREVIOUSLY FAILED BUT RUN FORCED VIA IGNORE FAILED OPTION!\n";
      } else {
        print R "\t\tIS PREVIOUSLY SCHEDULED, RUNNING, OR FAILED!\n";
        print R "\t\t\tSTATUS: ".$running_samples->{$analysis_url_str}."\n";
        $veto = 1;
      }
      # now check the number of bams == lane count (or this check is suppressed)
      if ($d->{total_lanes} == $d->{bams_count} || $ignore_lane_cnt || $force_run) {
        print R "\t\tLANE COUNT MATCHES OR IGNORED OR RUN FORCED: $ignore_lane_cnt $d->{total_lanes} $d->{bams_count}\n";
      } else {
        print R "\t\tLANE COUNT MISMATCH!\n";
        $veto=1;
      }
      if ($veto) { print R "\t\tCONCLUSION: WILL NOT SCHEDULE THIS SAMPLE FOR ALIGNMENT!\n\n"; }
      else {
        print R "\t\tCONCLUSION: SCHEDULING WORKFLOW FOR THIS SAMPLE!\n\n";
        schedule_workflow($d);
      }
    }
  }
}

sub read_sample_info {

  open OUT, ">xml_parse.log" or die;
  my $d = {};

  # PARSE XML
  my $parser = new XML::DOM::Parser;
  #my $doc = $parser->parsefile ("https://cghub.ucsc.edu/cghub/metadata/analysisDetail?participant_id=3f70c3e3-0131-466f-92aa-0a63ab3d4258");
  #system("lwp-download 'https://cghub.ucsc.edu/cghub/metadata/analysisDetail?study=TCGA_MUT_BENCHMARK_4&state=live' data.xml");
  #my $doc = $parser->parsefile ('https://cghub.ucsc.edu/cghub/metadata/analysisDetail?study=TCGA_MUT_BENCHMARK_4&state=live');
  #if (!$skip_down) { my $cmd = "mkdir -p xml; cgquery -s $gnos_url --all-states -o xml/data.xml 'study=*'"; print OUT "$cmd\n"; system($cmd); }
  # cgquery -o my_data.xml 'study=PAWG&state=live'
  if (!$skip_down) { 
    my $cmd = "mkdir -p xml; cgquery -s $gnos_url -o xml/data.xml 'study=*&state=live'"; 
    print OUT "$cmd\n"; 
    my $rsult = system($cmd); 
    if ($rsult) { print STDERR "Could not download data via cgquery!\n"; exit (1); }
  }
  my $doc = $parser->parsefile("xml/data.xml");

  # print OUT all HREF attributes of all CODEBASE elements
  my $nodes = $doc->getElementsByTagName ("Result");
  my $n = $nodes->getLength;

  # DEBUG
  #$n = 30;

  print OUT "\n";

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
      if (!$skip_down) { download($aurl, "xml/data_$i.xml"); }
      my $adoc = $parser->parsefile ("xml/data_$i.xml");
      my $adoc2 = XML::LibXML->new->parse_file("xml/data_$i.xml");
      my $analysisId = getVal($adoc, 'analysis_id');
      my $analysisDataURI = getVal($adoc, 'analysis_data_uri');
      my $submitterAliquotId = getCustomVal($adoc2, 'submitter_aliquot_id,submitter_sample_id');
      my $aliquotUUID = getVal($adoc, 'aliquot_id');
      my $aliquotId = getCustomVal($adoc2, 'aliquot_id,submitter_sample_id');
      my $submitterParticipantId = getCustomVal($adoc2, 'submitter_participant_id,submitter_donor_id');
      my $participantId = getCustomVal($adoc2, 'participant_id,submitter_donor_id');
      my $submitterSampleId = getCustomVal($adoc2, 'submitter_sample_id');
      # if donor_id defined then dealing with newer XML
      if (defined(getCustomVal($adoc2, 'submitter_donor_id')) && getCustomVal($adoc2, 'submitter_donor_id') ne '') {
        $submitterSampleId = getCustomVal($adoc2, 'submitter_specimen_id');
      }
      my $sampleId = getCustomVal($adoc2, 'sample_id,submitter_specimen_id');
      my $use_control = getCustomVal($adoc2, "use_cntl");
      my $alignment = getVal($adoc, "refassem_short_name");
      my $total_lanes = getCustomVal($adoc2, "total_lanes");
      my $sample_uuid = getXPathAttr($adoc2, "refname", "//ANALYSIS_SET/ANALYSIS/TARGETS/TARGET/\@refname");
      print OUT "ANALYSIS:  $analysisDataURI \n";
      print OUT "ANALYSISID: $analysisId\n";
      print OUT "PARTICIPANT ID: $participantId\n";
      print OUT "SAMPLE ID: $sampleId\n";
      print OUT "ALIQUOTID: $aliquotId\n";
      print OUT "SUBMITTER PARTICIPANT ID: $submitterParticipantId\n";
      print OUT "SUBMITTER SAMPLE ID: $submitterSampleId\n";
      print OUT "SUBMITTER ALIQUOTID: $submitterAliquotId\n";
      my $libName = getVal($adoc, 'LIBRARY_NAME');
      my $libStrategy = getVal($adoc, 'LIBRARY_STRATEGY');
      my $libSource = getVal($adoc, 'LIBRARY_SOURCE');
      print OUT "LibName: $libName LibStrategy: $libStrategy LibSource: $libSource\n";
      # get files
      # now if these are defined then move onto the next step
      if (defined($libName) && defined($libStrategy) && defined($libSource) && defined($analysisId) && defined($analysisDataURI)) {
        print OUT "  gtdownload -c gnostest.pem -v -d $analysisDataURI\n";
        #system "gtdownload -c gnostest.pem -vv -d $analysisId\n";
        print OUT "\n";
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{analysis_id}{$analysisId} = 1;
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{analysis_url}{$analysisDataURI} = 1;
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{library_name}{$libName} = 1;
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{library_strategy}{$libStrategy} = 1;
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{library_source}{$libSource} = 1;
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{alignment_genome}{$alignment} = 1;
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{use_control}{$use_control} = 1;
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{total_lanes}{$total_lanes} = 1;
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{submitter_participant_id}{$submitterParticipantId} = 1;
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{submitter_sample_id}{$submitterSampleId} = 1;
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{submitter_aliquot_id}{$submitterAliquotId} = 1;
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{sample_uuid}{$sample_uuid} = 1;
        # need to add
        # input_bam_paths=9c414428-9446-11e3-86c1-ab5c73f0e08b/hg19.chr22.5x.normal.bam
        # gnos_input_file_urls=https://gtrepo-ebi.annailabs.com/cghub/data/analysis/download/9c414428-9446-11e3-86c1-ab5c73f0e08b
        # gnos_input_metadata_urls=https://gtrepo-ebi.annailabs.com/cghub/metadata/analysisFull/9c414428-9446-11e3-86c1-ab5c73f0e08b

      } else {
        print OUT "ERROR: one or more critical fields not defined, will skip $analysisId\n\n";
        next;
      }
      my $files = readFiles($adoc);
      print OUT "FILE:\n";
      foreach my $file(keys %{$files}) {
        print OUT "  FILE: $file SIZE: ".$files->{$file}{size}." CHECKSUM: ".$files->{$file}{checksum}."\n";
        print OUT "  LOCAL FILE PATH: $analysisId/$file\n";
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{files}{$file}{size} = $files->{$file}{size};
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{files}{$file}{checksum} = $files->{$file}{checksum};
        $d->{$participantId}{$sampleId}{$alignment}{$aliquotId}{$libName}{files}{$file}{localpath} = "$analysisId/$file";
        # URLs?
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
          if ($node->toString() eq 'pending' || $node->toString() eq 'running' || $node->toString() eq 'scheduled' || $node->toString() eq 'submitted') { $running++; }
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
