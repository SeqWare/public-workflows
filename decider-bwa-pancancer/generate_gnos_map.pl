use strict;
use Getopt::Long;
use POSIX;

my $output = "index.html";

if (scalar(@ARGV) != 2) { print "USAGE: generate_gnos_map.pl --output index.html"; }

GetOptions("output=s" => \$output);

my $t = `cat template/map.html`;

# 3000 specimens for ICGC see https://docs.google.com/spreadsheet/ccc?key=0AnBqxOn9BY8ldGN6dnNqNmxiYlhBNUlCZ3VIYVpPRlE&usp=sharing#gid=0
my $specimens = 3000;
my $total_aligned = 0;
my $total_unaligned = 0;

# queries each gnos repo
foreach my $i ("gtrepo-bsc", "gtrepo-dkfz", "gtrepo-osdc", "gtrepo-etri", "gtrepo-ebi", "gtrepo-tokyo") {
#foreach my $i ("gtrepo-osdc") {
  system("rm -rf xml");
  my $cmd = "perl workflow_decider.pl --gnos-url https://$i.annailabs.com --report $i.log --ignore-lane-count --upload-results --test";
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

open OUT, ">$output" or die;
print OUT $t;
close OUT;

# now cleanup
system("rm -rf xml");

