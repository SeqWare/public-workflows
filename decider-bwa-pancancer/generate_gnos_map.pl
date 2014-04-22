use strict;
use Getopt::Long;

my $output = "index.html";

if (scalar(@ARGV) != 2) { print "USAGE: generate_gnos_map.pl --output index.html"; }

GetOptions("output=s" => \$output);

# queries each gnos repo
foreach my $i ("gtrepo-bsc", "gtrepo-dkfz", "gtrepo-osdc", "gtrepo-etri", "gtrepo-ebi") {
  my $cmd = "perl workflow_decider.pl --gnos-url https://$i.annailabs.com --report $i.log --ignore-lane-count --upload-results --test &> /dev/null";
  print "$cmd";
  my $values = `cat $i.log | grep 'ALIGNMENT:' | sort | uniq -c`;
  my @v = split /\n/;
  my $aligned = 0;
  my $notaligned = 0;
  foreach my $line (@v) {
    chomp $line;
    if ($line =~ /\s+(\d+)\s+ALIGNMENT: unaligned/) {
      $notaligned = $1;
    } elsif ($line =~ /\s+(\d+)\s+ALIGNMENT:) {
      $aligned += $1;
    }
  }
  print "$i ALIGNED $aligned UNALIGNED: $notaligned\n";
  die;
}
