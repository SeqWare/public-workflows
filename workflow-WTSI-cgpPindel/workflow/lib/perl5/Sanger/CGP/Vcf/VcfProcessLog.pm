package Sanger::CGP::Vcf::VcfProcessLog;

##########LICENCE##########
# Copyright (c) 2014 Genome Research Ltd. 
#  
# Author: Jon Hinton <cgpit@sanger.ac.uk> 
#  
# This file is part of cgpVcf. 
#  
# cgpVcf is free software: you can redistribute it and/or modify it under 
# the terms of the GNU Affero General Public License as published by the Free 
# Software Foundation; either version 3 of the License, or (at your option) any 
# later version. 
#  
# This program is distributed in the hope that it will be useful, but WITHOUT 
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more 
# details. 
#  
# You should have received a copy of the GNU Affero General Public License 
# along with this program. If not, see <http://www.gnu.org/licenses/>.
##########LICENCE##########


use Sanger::CGP::Vcf;
our $VERSION = Sanger::CGP::Vcf->VERSION;

use strict;
use warnings FATAL => 'all';

1;

sub new{
	my $proto = shift;
	my (%args) = @_;
	my $class = ref($proto) || $proto;

	my $self = {
		_input_vcf        => $args{'-input_vcf'},
		_input_vcf_source => $args{'-input_vcf_source'},
		_input_vcf_ver    => $args{'-input_vcf_ver'},
		_input_vcf_params  => $args{'-input_vcf_params'},
	};
    bless $self, $class;
    return $self;
}

sub input_vcf{
	my($self,$value) = @_;
	$self->{_input_vcf} = $value if defined $value;
	return $self->{_input_vcf};
}

sub input_vcf_source{
	my($self,$value) = @_;
	$self->{_input_vcf_source} = $value if defined $value;
	return $self->{_input_vcf_source};
}

sub input_vcf_ver{
	my($self,$value) = @_;
	$self->{_input_vcf_ver} = $value if defined $value;
	return $self->{_input_vcf_ver};
}

sub input_vcf_params{
	my($self,$value) = @_;
	$self->{_input_vcf_params} = $value if defined $value;
	return $self->{_input_vcf_params};
}
