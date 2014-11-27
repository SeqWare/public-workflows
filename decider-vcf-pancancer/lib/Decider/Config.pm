package Decider::Config;

use common::sense;

use autodie qw(:all);

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Config::Simple;

use Data::Dumper;

### merges command line flags with configurations in the decider config file
sub get {
    my %ARGV = %{$_[1]};

    my $cfg = new Config::Simple();

    $cfg->read("$Bin/../$ARGV{'--decider-config'}");
    
    my %decider_config = $cfg->vars();

    my @general_seqware_clusters = split ';', $decider_config{'general.seqware-clusters'};
    $ARGV{'--seqware-clusters'} //= \@general_seqware_clusters;

    foreach my $config_file (@{$ARGV{'--seqware-clusters'}}) {
        die "file does not exist: $config_file" unless (-f $config_file);
    }
 
    # General 
    $ARGV{'--pem-file'} //= $decider_config{'general.pem-file'};
    die 'Pem file needs to be defined' unless $ARGV{'--pem-file'};
    
    $ARGV{'--workflow-version'} //= $decider_config{'general.workflow-version'};
    die 'Workflow version needs to be defined' unless $ARGV{'--workflow-version'};
    
    $ARGV{'--gnos-url'} //= $decider_config{'general.gnos-url'};
    die 'GNOS url needs to be defined' unless $ARGV{'--gnos-url'};
    
    $ARGV{'--working-dir'} //= $decider_config{'general.working-dir'};
    die 'Working dir needs to be defined' unless $ARGV{'--working-dir'};
    
    $ARGV{'--use-cached-analysis'} = 1 
        if ($decider_config{'general.use-cached-analysis'} eq 'true');
    
    $ARGV{'--seqware-settings'} //= $decider_config{'general.seqware-settings'};
        die 'Seqware settings needs to be defined' unless $ARGV{'--seqware-settings'};
    
    $ARGV{'--report'} //= $decider_config{'general.report'};
        die 'Report needs to be defined' unless $ARGV{'--report'};
    
    $ARGV{'--use-live-cached'} = 1 
        if ($decider_config{'general.use-live-cached'} eq 'true');
    
    $ARGV{'--lwp-download-timeout'} //= $decider_config{'general.lwp-download-timeout'};
     die 'LWP download timeout needs to be defined' unless $ARGV{'--lwp-download-timeout'};

    $ARGV{'--tabix-url'} //= $decider_config{'general.tabix-url'};
    die 'Tabix url needs to be defined' unless $ARGV{'--tabix-url'};
    
    ### Schedule
    
    $ARGV{'--schedule-ignore-failed'} = 1 
        if ($decider_config{'scheduling.ignore-failed'} eq 'true');
    
    $ARGV{'--schedule-whitelist-sample'} //= $decider_config{'scheduling.whitelist-sample'};
    
    $ARGV{'--schedule-blacklist-sample'} //= $decider_config{'scheduling.blacklist-sample'};
    
    $ARGV{'--schedule-whitelist-donor'} //= $decider_config{'scheduling.whitelist-donor'};
    
    $ARGV{'--schedule-blacklist-donor'} //= $decider_config{'scheduling.blacklist-donor'};

    $ARGV{'--schedule-ignore-lane-count'} = 1 
        if ($decider_config{'scheduling.ignore-lane-count'} eq 'true');
    
    $ARGV{'--schedule-force-run'} = 1 
        if ($decider_config{'scheduling.force-run'} eq 'true');
    
    ### Workflow

    $ARGV{'--workflow-skip-scheduling'} = 1
        if ($decider_config{'workflow.skip-scheduling'} eq 'true');
    
    $ARGV{'--workflow-upload-results'} = 1 
        if ($decider_config{'workflow.upload-results'} eq 'true');
    
    $ARGV{'--workflow-skip-gtdownload'} = 1 
        if ($decider_config{'workflow.skip-gtdownload'} eq 'true');
    
    $ARGV{'--workflow-skip-gtupload'} = 1 
        if ($decider_config{'workflow.skip-gtupload'} eq 'true');
    
    
    $ARGV{'--workflow-output-dir'} //= $decider_config {'workflow.output-dir'};
    
    $ARGV{'--workflow-output-prefix'} //= $decider_config {'workflow.output-prefix'};
    
    $ARGV{'--workflow-input-prefix'} //= $decider_config {'workflow.input-prefix'};

    $ARGV{'--cores-addressable'} //= $decider_config{'workflow.cores-addressable'};

    return \%ARGV;
}

1
