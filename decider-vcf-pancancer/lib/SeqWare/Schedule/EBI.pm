package SeqWare::Schedule::EBI;
# subclass schedule for EBI-specific variant calling workflow

#use common::sense;
use Data::Dumper;
use parent SeqWare::Schedule;
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
    
    my $ini_path = "$Bin/../conf/ini/workflow-$workflow_version.ini";
    die "ini template does not exist: $ini_path" unless (-e $ini_path);
    my $workflow_ini = new Config::Simple($ini_path) || die "No workflow ini"; 

    my $donor_id = $donor->{donor_id};

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

    my ($assembly) = keys %{$donor->{alignment_genome}};
    my ($seq_type) = keys %{$donor->{library_strategy}};

    $workflow_ini->param('coresAddressable' => $threads);
    $workflow_ini->param('tabixSrvUri'      => $tabix_url);

    $workflow_ini->param('tumourAnalysisId' => join(':',@tumor_analysis));
    $workflow_ini->param('tumourAliquotId'  => join(':',@tumor_aliquot));
    $workflow_ini->param('tumourBam'        => join(':',@tumor_bam));

    $workflow_ini->param('controlAnalysisId' => join(':',@normal_analysis));
    $workflow_ini->param('controlAliquotId'  => join(':',@normal_aliquot));
    $workflow_ini->param('controlBam'        => join(':',@normal_bam));

    $workflow_ini->param('pemFile'           => $pem_file);
    $workflow_ini->param('gnosServer'        => $gnos_url);
    
    $workflow_ini->param('assembly'          => $assembly);
    $workflow_ini->param('species'           => 'human'); # will always be, no?
    $workflow_ini->param('seqType'           => $seq_type);
    $workflow_ini->param('gender'            => 'L'); # not linked
    
    $workflow_ini->param('donor_id'          => $donor->{donor_id});    
  
    print "$Bin/../$working_dir/samples/$center_name/$donor_id/workflow.ini\n";
    $workflow_ini->write("$Bin/../$working_dir/samples/$center_name/$donor_id/workflow.ini");
}

1;
