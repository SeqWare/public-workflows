package SeqWare::Schedule::Sanger;
# subclass schedule for Sanger-specific variant calling workflow

use common::sense;
use Data::Dumper;
use parent 'SeqWare::Schedule';
use SeqWare::Schedule::Ini;
use FindBin qw($Bin);
use warnings;
use strict;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}


sub create_settings_file {
    my $self = shift;
    my (
	$donor,
	$seqware_settings_file, 
	$url, 
	$username, 
	$password, 
	$working_dir, 
	$center_name) = @_;

    my $settings = new Config::Simple("$Bin/../conf/ini/$seqware_settings_file");

    $url //= '<SEQWARE URL>';
    $username //= '<SEQWARE USER NAME>';
    $password //= '<SEQWARE PASSWORD>';

    $settings->param('SW_REST_URL', $url);
    $settings->param('SW_REST_USER', $username);
    $settings->param('SW_REST_PASS',$password);

    my $donor_id = $donor->{donor_id};
    $settings->write("$Bin/../$working_dir/samples/$center_name/$donor_id/settings");
}

sub create_workflow_ini {
    my $self = shift;
    my (
	$donor,
	$workflow_version, 
	$gnos_url, 
	$threads, 
	$skip_gtdownload, 
	$skip_gtupload, 
	$upload_results, 
	$output_prefix, 
	$output_dir, 
	$working_dir, 
	$center_name, 
	$tabix_url,
	$pem_file) = @_;
    
    # Read in the default data
    my $defaults = "$Bin/../conf/ini/settings.conf";
    die "Settings file does not exist: $defaults" unless (-e $defaults);
    open DEF, $defaults or die $!; 
    my $data = {};
    while(<DEF>) {
	chomp;
	if(/(\S+)\s*=\s*(\S+)/) {
	    my $key = $1;
	    my $val = $2;
	    $data->{$key} = $val;
	}
    }

    my @normal_alignments = keys %{$donor->{normal}};
    my @tumor_alignments  = keys %{$donor->{tumor}};

    my (@normal_bam,@normal_analysis,@normal_aliquot);
    for my $aln_id (@normal_alignments) {
	push @normal_bam, $donor->{bam_ids}->{$aln_id};
	push @normal_analysis, $donor->{analysis_ids}->{$aln_id};
	push @normal_aliquot, $donor->{aliquot_ids}->{$aln_id};
    }
    my (@tumor_bam,@tumor_analysis,@tumor_aliquot);
    for my $aln_id (@tumor_alignments) {
	push @tumor_bam, $donor->{bam_ids}->{$aln_id};
	push @tumor_analysis, $donor->{analysis_ids}->{$aln_id};
	push @tumor_aliquot, $donor->{aliquot_ids}->{$aln_id};
    }

    $data->{'coresAddressable'}  = $threads;
    $data->{'tabixSrvUri'}       = $tabix_url;
    $data->{'tumourAnalysisIds'} = join(':',@tumor_analysis);
    $data->{'tumourAliquotIds'}  = join(':',@tumor_aliquot);
    $data->{'tumourBams'}        = join(':',@tumor_bam);
    $data->{'controlAnalysisId'} = join(':',@normal_analysis);
    $data->{'controlAliquotId'}  = join(':',@normal_aliquot);
    $data->{'controlBam'}        = join(':',@normal_bam);
    $data->{'pemFile'}           = $pem_file;
    $data->{'gnosServer'}        = $gnos_url;
    $data->{'donor_id'}          = $donor->{donor_id};    
    
    my $template = "$Bin/../conf/ini/workflow-$workflow_version.ini";

    my $ini_factory = SeqWare::Schedule::Ini->new;
    $ini_factory->create_ini_file("$working_dir/ini",$template,$data,$donor->{donor_id});
}

1;
