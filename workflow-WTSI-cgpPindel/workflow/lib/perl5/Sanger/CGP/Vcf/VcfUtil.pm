package Sanger::CGP::Vcf::VcfUtil;

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
use Carp;
use Vcf;

1;

=head gen_tn_vcf_header

A string generator for generating a uniform header section for NORMAL/TUMOUR comparisons. Useful if you do not want to include the VcfTools lib.

@param1 wt_sample      - a Sanger::CGP::Pindel::OutputGen::Sample object representing the wild type sample.

@param2 mt_sample      - a Sanger::CGP::Pindel::OutputGen::Sample object representing the mutant type sample.

@param3 contigs        - an array-ref of Sanger::CGP::Pindel::OutputGen::Contig object.

@param4 reference_name - a String containing the name of the reference used in the VCF.

@param5 input_source   - a String containing the name and version of the application or source of the VCF data.

@param6 info           - an array-ref of hash-refs containing VCF formatted INFO data.

@param7 format         - an array-ref of hash-refs containing VCF formatted FORMAT data.

@param8 other          - an array-ref of hash-refs containing VCF formatted header data.

@returns               - String containing a fully formatted VCF header.

=cut
sub gen_tn_vcf_header{
	my($wt_sample, $mt_sample, $contigs, $process_logs, $reference_name, $input_source, $info, $format, $other) = @_;
	my $vcf = Vcf->new(version=>'4.1');
	init_tn_vcf_header($vcf, $wt_sample, $mt_sample, $contigs, $process_logs, $reference_name, $input_source, $info, $format, $other);
	return $vcf->format_header();
}

=head init_tn_vcf_header

Initialises the header of a Vcf object for NORMAL/TUMOUR comparisons. Useful if you do not want to include the VcfTools lib.

@param1 vcf            - a Vcf object.

@param2 wt_sample      - a Sanger::CGP::Vcf::Sample object representing the wild type sample.

@param3 mt_sample      - a Sanger::CGP::Vcf::Sample object representing the mutant type sample.

@param4 contigs        - an array-ref of Sanger::CGP::Vcf::Contig objects.

@param5 process_logs   - an array-ref of Sanger::CGP::Vcf::VcfProcessLog objects.

@param6 reference_name - a String containing the name of the reference used in the VCF.

@param7 input_source   - a String containing the name and version of the application or source of the VCF data.

@param8 info           - an array-ref of hash-refs containing VCF formatted INFO data.

@param9 format         - an array-ref of hash-refs containing VCF formatted FORMAT data.

@param10 other         - an array-ref of hash-refs containing VCF formatted header data.

=cut
sub init_tn_vcf_header{
	my($vcf, $wt_sample, $mt_sample, $contigs, $process_logs, $reference_name, $input_source, $info, $format, $other) = @_;

	$vcf->add_header_line( { key => 'fileDate', value => get_date() } );
	$vcf->add_header_line( { key => 'source',   value => $input_source }, 'append' => 1 );
	$vcf->add_header_line( { key => 'reference', value => $reference_name } );

	for my $contig (@{$contigs}){
		add_vcf_contig($vcf,$contig)
	}

	for my $inf (@{$info}){
		$vcf->add_header_line($inf);
	}

	for my $for (@{$format}){
		$vcf->add_header_line($for);
	}

	for my $oth (@{$other}){
		$vcf->add_header_line($oth);
	}

	for my $process_log (@{$process_logs}){
		add_vcf_process_log($vcf,$process_log)
	}

	add_vcf_sample($vcf, $wt_sample, 'NORMAL');
	add_vcf_sample($vcf, $mt_sample, 'TUMOUR');
}

=head add_vcf_sample

Adds a Sanger::CGP::Pindel::OutputGen::Sample object to a Vcf header object. The order of entry is important as it determines the order of the data in the resulting .vcf file.

@param1 vcf    - a Vcf object.

@param2 sample - a Sanger::CGP::Vcf::Sample object.

@param3 id     - String, the id of the sample to be displayed in the VCF file.

=cut
sub add_vcf_sample{
	my($vcf, $sample, $id) = @_;

	$id = $sample->name unless defined $id and $id ne q{};

	my %input_hash = (
		key  => 'SAMPLE',
		ID   => $id,
		SampleName => $sample->name
	); ## will use the natural order of the hash I think...


	#push %input_hash , 'Description', $sample->description if $sample->description;

	$input_hash{Description} = $sample->description if $sample->description;
	$input_hash{Study} = $sample->study if $sample->study;
	$input_hash{Source} = $sample->accession_source if $sample->accession_source;
	$input_hash{Accession} = $sample->accession if $sample->accession;
	$input_hash{Platform} = $sample->platform if $sample->platform;
	$input_hash{Protocol} = $sample->seq_protocol if $sample->seq_protocol;

	$vcf->add_header_line(\%input_hash);
	$vcf->add_columns( $id );
}

=head add_vcf_contig

Adds a Sanger::CGP::Pindel::OutputGen::Contig object to a Vcf header object.

@param1 vcf    - a Vcf object.

@param2 contig - a Sanger::CGP::Vcf::Contig object.

=cut
sub add_vcf_contig{
	my($vcf, $contig) = @_;

	my %input_hash = (
		key      => 'contig',
		ID       => $contig->name,
		assembly => $contig->assembly,
		length   => $contig->length,
		species  => $contig->species,
	); ## will use the natural order of the hash I think...

	$input_hash{md5} = $contig->checksum if $contig->checksum;
	$vcf->add_header_line(\%input_hash);
}

=head add_vcf_process_log

Adds a Sanger::CGP::Vcf::VcfProcessLog object to a Vcf header object.

@param1 vcf         - a Vcf object.

@param2 process_log - a Sanger::CGP::Pindel::OutputGen::VcfProcessLog object.

=cut
sub add_vcf_process_log{
	my($vcf, $process_log) = @_;

	my %input_hash = (key => 'vcfProcessLog');
	$input_hash{InputVCF} = $process_log->input_vcf if $process_log->input_vcf;
	$input_hash{InputVCFSource} = $process_log->input_vcf_source if $process_log->input_vcf_source;
	$input_hash{InputVCFVer} = $process_log->input_vcf_ver if $process_log->input_vcf_ver;
	$input_hash{InputVCFParam} = $process_log->input_vcf_params if $process_log->input_vcf_params;
	$vcf->add_header_line(\%input_hash);
}

sub get_date {
	my @timeData = localtime(time);
	my $year     = 1900 + $timeData[5];
	return
	    $year
	  . sprintf( "%02d", $timeData[4]+1 )
	  . sprintf( "%02d", $timeData[3] );
}
