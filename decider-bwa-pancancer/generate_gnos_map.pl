use strict;
use Getopt::Long;
use POSIX;

my $output = "index.html";

if (scalar(@ARGV) != 2) { print "USAGE: generate_gnos_map.pl --output index.html"; }

GetOptions("output=s" => \$output);

my $t = `cat template/map.html`;

# queries each gnos repo
#foreach my $i ("gtrepo-bsc", "gtrepo-dkfz", "gtrepo-osdc", "gtrepo-etri", "gtrepo-ebi") {
foreach my $i ("gtrepo-bsc", "gtrepo-dkfz", "gtrepo-osdc", "gtrepo-ebi") {
#foreach my $i ("gtrepo-bsc", "gtrepo-dkfz", "gtrepo-osdc") {
  system("rm -rf xml");
  my $cmd = "perl workflow_decider.pl --gnos-url https://$i.annailabs.com --report $i.log --ignore-lane-count --upload-results --test";
  print "$cmd";
  system($cmd);
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
  my $logalign = 6; if ($aligned > 6) { $logalign = ceil(3 * (log($aligned)/log(2))); }
  my $lognot = 6; if ($notaligned > 6) { $lognot = ceil(3 * (log($notaligned)/log(2))); }
  $t =~ s/$i.aligned/$aligned/g;
  $t =~ s/$i.unaligned/$notaligned/g;
  $t =~ s/$i.log.aligned/$logalign/g;
  $t =~ s/$i.log.unaligned/$lognot/g;
}
open OUT, ">$output" or die;
print OUT $t;
close OUT;
