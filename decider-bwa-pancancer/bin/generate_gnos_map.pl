use strict;
use Getopt::Long;
use POSIX;
use XML::DOM;
use Data::Dumper;
use JSON;
use XML::LibXML;
use Cwd;

my $output = "index.html";
my $cluster_json = "cluster.json";
my $template = "template/map.html";

if (scalar(@ARGV) != 6) { die "USAGE: generate_gnos_map.pl --output index.html --cluster-json cluster.json --template template/map.html"; }

GetOptions("output=s" => \$output, "cluster-json=s" => \$cluster_json, "template=s" => \$template);


my $t = `cat $template`;

# 3000 specimens for ICGC, 2000 for TCGA see https://docs.google.com/spreadsheet/ccc?key=0AnBqxOn9BY8ldGN6dnNqNmxiYlhBNUlCZ3VIYVpPRlE&usp=sharing#gid=0
my $specimens = 5000;
my $total_aligned = 0;
my $total_unaligned = 0;

# queries each gnos repo
foreach my $i ("gtrepo-bsc", "gtrepo-dkfz", "gtrepo-osdc", "gtrepo-etri", "gtrepo-ebi", "gtrepo-riken", "gtrepo-cghub") {
#foreach my $i ("gtrepo-cghub") {
  #system("rm -rf xml");
  my $cmd = "perl workflow_decider.pl --gnos-url https://$i.annailabs.com --report $i.log --ignore-lane-count --upload-results --test --working-dir $i --skip-cached";
  # hack for CGHub
  if ($i =~ /gtrepo-cghub/) {
    $cmd = "perl workflow_decider.pl --gnos-url https://cghub.ucsc.edu --report $i.log --ignore-lane-count --upload-results --test --working-dir $i --skip-cached";
  }
  print "$cmd";
  my $result = system($cmd);
  if ($result) {
    print "ERROR: can't communicate with GNOS"; 
    $t =~ s/$i.aligned/offline/g;
    $t =~ s/$i.unaligned/offline/g;
    $t =~ s/$i.log.aligned/6/g;
    $t =~ s/$i.log.unaligned/6/g;
    next;
  }
  my $values = `cat $i.log | grep 'ALIGNMENT:' | sort | uniq -c`;
  my @v = split /\n/, $values;
  my $aligned = 0;
  my $notaligned = 0;
  foreach my $line (@v) {
    chomp $line;
    if ($line =~ /\s+(\d+)\s+ALIGNMENT: unaligned/) {
      $notaligned = $1;
    } elsif ($line =~ /\s+(\d+)\s+ALIGNMENT:/) {
      $aligned += $1;
    }
  }
  print "$i ALIGNED $aligned UNALIGNED: $notaligned\n";
  $total_aligned += $aligned;
  $total_unaligned += $notaligned;
  my $logalign = 6; if ($aligned > 6) { $logalign = ceil(3 * (log($aligned)/log(2))); }
  my $lognot = 6; if ($notaligned > 6) { $lognot = ceil(3 * (log($notaligned)/log(2))); }
  $t =~ s/$i.aligned/$aligned/g;
  $t =~ s/$i.unaligned/$notaligned/g;
  $t =~ s/$i.log.aligned/$logalign/g;
  $t =~ s/$i.log.unaligned/$lognot/g;
}

# fill in totals
my $total_aligned_percent = sprintf("%.2f", ($total_aligned/$specimens)*100)."%";
my $total_unaligned_percent = sprintf("%.2f", ($total_unaligned/$specimens)*100)."%";
$t =~ s/total.aligned.percent/$total_aligned_percent/g;
$t =~ s/total.unaligned.percent/$total_unaligned_percent/g;
$t =~ s/total.aligned/$total_aligned/g;
$t =~ s/total.unaligned/$total_unaligned/g;
$t =~ s/total.specimens/$specimens/g;

my ($cluster_info, $running_samples) = read_cluster_info($cluster_json);
#print Dumper($cluster_info);
#print Dumper($running_samples);
# now print cluster info
my $ct = "<table border=1>
<tr><th>Cluster</th><th>Submitted</th><th>Running</th><th>Completed</th><th>Failed</th><th></th></tr>
";
foreach my $cluster (keys %{$cluster_info}) {
  my $sub = $cluster_info->{$cluster}{submitted_workflows};
  my $run = $cluster_info->{$cluster}{running_workflows};
  my $comp = $cluster_info->{$cluster}{completed_workflows};
  my $fail = $cluster_info->{$cluster}{failed_workflows};
  $ct .= "<tr><td>$cluster</td><td>$sub</td><td>$run</td><td>$comp</td><td>$fail</td><td>Workflows</td></tr>\n";
}
$ct .= "</table>";
$t =~ s/cluster.table/$ct/g;

open OUT, ">$output" or die;
print OUT $t;
close OUT;

# now cleanup
#system("rm -rf xml");

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
      print "EXAMINING CLUSER: $c\n";
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
        print  "\tWORKFLOWS ON THIS CLUSTER\n";
        my $i=0;
        for my $node ($dom2->findnodes('//WorkflowRunList2/list/status/text()')) {
          $i++;
          print "\t\tWORKFLOW: ".$acc." STATUS: ".$node->toString()."\n";
          if ($node->toString() eq 'running' ) { $json->{$c}{running_workflows}++; }
          elsif ($node->toString() eq 'pending' || $node->toString() eq 'scheduled' || $node->toString() eq 'submitted') { $json->{$c}{submitted_workflows}++; }
          elsif ($node->toString() eq 'failed') { $json->{$c}{failed_workflows}++; }
          elsif ($node->toString() eq 'completed') { $json->{$c}{completed_workflows}++; }
          $json->{$c}{total_workflows}++;
          # find running samples
          my $j=0;
          for my $node2 ($dom2->findnodes('//WorkflowRunList2/list/iniFile/text()')) {
            $j++;
            my $ini_contents = $node2->toString();
            $ini_contents =~ /gnos_input_metadata_urls=(\S+)/;
            my @urls = split /,/, $1;
            my $sorted_urls = join(",", sort @urls);
            if ($i==$j) { $run_samples->{$sorted_urls} = $node->toString(); print "\t\t\tINPUTS: $sorted_urls\n"; }
          }
          $j=0;
          for my $node2 ($dom2->findnodes('//WorkflowRunList2/list/currentWorkingDir/text()')) {
            $j++;
            if ($i==$j) { my $txt = $node2->toString(); print "\t\t\tCWD: $txt\n"; }
          }
          $j=0;
          for my $node2 ($dom2->findnodes('//WorkflowRunList2/list/swAccession/text()')) {
            $j++;
            if ($i==$j) { my $txt = $node2->toString(); print "\t\t\tWORKFLOW ACCESSION: $txt\n"; }
          }
        }
        # if there are no running workflows on this cluster it's a candidate
        $d->{"$c"} = $json->{$c};
      }
    }
  }
  #print "Final cluster list:\n";
  #print Dumper($d);
  return($d, $run_samples);

}
