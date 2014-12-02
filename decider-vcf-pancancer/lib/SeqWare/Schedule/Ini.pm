package SeqWare::Schedule::Ini;
# A class to deal with ini file creation via template

use common::sense;
use Template;
use Data::Dumper;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

sub create_ini_file {
    my $self = shift;
    my ($output_dir,
	$template,
	$data) = @_;

    my $def = {};
    my $tt = Template->new(ABSOLUTE => 1);

    my $tumor_id = $data->{tumourAliquotIds};

    # make a working dir
    system("mkdir -p $output_dir") unless -d $output_dir;
    $output_dir .= "/$tumor_id";
    system("mkdir -p $output_dir") unless -d $output_dir;

    # make an ini file
    say "Making ini file at $output_dir/workflow.ini";
    $tt->process($template, $data, "$output_dir/workflow.ini") || die $tt->error;
}

1;
