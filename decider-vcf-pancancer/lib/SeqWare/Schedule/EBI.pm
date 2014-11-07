package SeqWare::Schedule::EBI;
# subclass schedule for EBI-specific variant calling workflow

use parent SeqWare::Schedule;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}




1;
