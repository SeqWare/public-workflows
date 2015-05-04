use strict;
use JSON;


my $ret = { "timing_metrics" => [] };

# now go ahead and read that index file for timing
my $download_timing = read_timing("download_timing.txt");
my $reference_timing = read_timing("reference_timing.txt");
my $dkfz_reference_timing = read_timing("dkfz_reference_timing.txt");
my $dkfz_timing = read_timing("dkfz_timing.txt");
my $embl_timing = read_timing("embl_timing.txt");

# fill in the data structure
push @{ $ret->{timing_metrics} }, { "workflow" =>  { "download_timing_seconds" => $download_timing,
                                                       "reference_timing_seconds" => $reference_timing,
                                                       "dkfz_reference_seconds" => $dkfz_reference_timing,
                                                       "dkfz_timing_seconds" => $dkfz_timing,
                                                       "embl_timing_seconds" => $embl_timing
                                                   }
                                  };

print to_json($ret);


sub read_timing {
    my ($file) = @_;

    open IN, '<', $file or return "not_collected"; # very quick workaround to deal with no download_timing file generated due to skip gtdownload option. Brian, please handle it as you see it appropriate
    my $start = <IN>;
    my $stop = <IN>;
    chomp $start;
    chomp $stop;
    my $delta = $stop - $start;
    close IN;

    return $delta;
}