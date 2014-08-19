use strict;
use Getopt::Long;

# this is just a quick script for running the old and new decider at each of
# the GNOS sites and doing a diff on the resulting report for each site.

my $bin1;
my $bin2;
my @gtrepos;

GetOptions(
  "bin1=s" => \$bin1,
  "bin2=s" => \$bin2,
  "gtrepo=s" => \@gtrepos,
);

if (scalar(@gtrepos) == 0) {
  @gtrepos = ("bsc", "osdc-icgc", "osdc-tcga", "dkfz", "ebi", "etri", "riken", "cghub");
} 

run("echo '{}' > empty.json");
run("mkdir -p reports/bin1");
run("mkdir -p reports/bin2");
run("mkdir -p working/bin1");
run("mkdir -p working/bin2");
run("mkdir -p diff_reports");

foreach my $gnos (@gtrepos) {
  print "DOWNLOADING REPORTS FOR: $gnos\n";
  my $cmd1 = "perl $bin1 --gnos-url https://gtrepo-$gnos.annailabs.com --cluster-json empty.json --working-dir working/bin1/$gnos --test --force-run --report reports/bin1/$gnos.report --skip-cached";
  run($cmd1);
  my $cmd2 = "perl $bin2 --gnos-url https://gtrepo-$gnos.annailabs.com --seqware-clusters empty.json --working-dir working/bin2/$gnos --report reports/bin2/$gnos.report --use-live-cached --workflow-skip-scheduling --workflow-version 2.6.0";
  run($cmd2);
  # now diff the two reports
  run("diff reports/bin1/$gnos.report reports/bin2/$gnos.report > diff_reports/$gnos.diff");
  if (-s "diff_reports/$gnos.diff") {
    print "NOT EQUAL: the output of reports/bin1/$gnos.report reports/bin2/$gnos.report is not equal, please look at diff_reports/$gnos.diff\n";
  } else {
    print "REPORTS EQUAL: reports/bin1/$gnos.report reports/bin2/$gnos.report are equal\n";
  }
}

sub run {
  my ($cmd) = @_;
  print "CMD: $cmd\n";
  return(system($cmd));
}
