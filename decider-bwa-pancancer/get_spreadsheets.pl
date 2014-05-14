#!/usr/bin/perl
# File: get_spreadsheets.pl by Marc Perry
#
# Concept: I would like to create a command line tool
# that will let me quickly download a GDocs spreadsheet
#
# Last Updated: 2014-05-13, Status: basic functionality working

use strict;
use warnings;
use Net::Google::Spreadsheets;
use DateTime;
use DateTime::Duration;
use Data::Dumper;
use Carp qw( verbose );

# globally overriding calls to die, and sending them to Carp
$SIG{__DIE__} = sub { &Carp::confess };

# The actual column header fields in the first row of all of these spreadsheets:
my @real_header = ( 'Study', 'dcc_project_code', 'Accession Identifier', 'submitter_donor_id', 'submitter_specimen_id', 'submitter_sample_id', 'Readgroup SM UUID', 'dcc_specimen_type', 'Normal/Tumor Designation', 'Matching Normal or Tumour ICGC Sample Identifier', 'Sequencing Strategy', 'Number of BAM files/sample', 'Target Upload Date (DD/MM/YYYY)', 'Actual Upload Date (DD/MM/YYYY)', );

# The mangled column header fields created when Net::Google::Spreadsheets parses the GoogleDocs:
my @header = ( 'study', 'dccprojectcode', 'accessionidentifier', 'submitterdonorid', 'submitterspecimenid', 'submittersampleid', 'readgroupsmuuid', 'dccspecimentype', 'normaltumordesignation', 'matchingnormalortumouricgcsampleidentifier', 'sequencingstrategy', 'numberofbamfilessample', 'targetuploaddateddmmyyyy', 'actualuploaddateddmmyyyy', );

my %gkeys = ( 'BRCA-EU' => '0AoQ6zq-rG38-dDhvU0VZNk4wMGpDUk1NaWZHMG5LLWc',
              'BRCA-UK' => '0ApWzavEDzSJddDAzdjVPbVVubHV6UDgxSEcxa0F3bEE',
              'BTCA-SG' => '0ApWzavEDzSJddGhFak1rZEJmUHFjOWR3MTRPVndrVlE',
              'CLLE-ES' => '0ApWzavEDzSJddFlnVTNmVXA5dWFNWlBhbVlpTFdWTlE',
              'EOPC-DE' => '0ApWzavEDzSJddEUtMUdHTFlrajA5Y0poQmFqTVdpY3c',
              'ESAD-UK' => '0ApWzavEDzSJddENiS3F2V1BIU3diVGpRd3hPeHkyWXc',
              'LAML-KR' => '0ApWzavEDzSJddEJfUVJ2TEd0aGJJazM3RktXVmtGX1E',
              'LIRI-JP' => '0ApWzavEDzSJddExGbTZfSG1HZmZJTEUxVjN0NzZNNlE',
              'MALY-DE' => '0ApWzavEDzSJddFdLWlJ3YkxoMzA4TnB4QXhkQ0VuWVE',
              'PACA-CA' => '0ApWzavEDzSJddF9BUXpLa0Qzd0JJRXJZWllmV2V6Wnc',
              'PBCA-DE' => '0ApWzavEDzSJddDAyT2x1WmQ5dkl0NENnVTdPSXBLRXc',
              'PRAD-UK' => '0ApWzavEDzSJddEZ6aUdVMnVoX1FEdVZ2REswY3pVMGc',
              'LICA-FR' => '0ApWzavEDzSJddFctcDhqajNtWVM5aWxzQzByTzl2MEE',
              'ORCA-IN' => '0ApWzavEDzSJddEdwaHBVdlJqMlVfYjd5SFRqek9PbHc',
              'OV-AU'   => '0ApWzavEDzSJddFBieGxUQ204dGdzLVg0T3Zfb1NXNnc',
              'GACA-CN' => '0ApWzavEDzSJddFBNZmJtREV2eG1ybkZCZ2FoV1g2T3c',
);

my @now = localtime();
my $timestamp = sprintf("%04d_%02d_%02d_%02d_%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1]);

# Create a new Net::Google::Spreadsheets object:
my $service = Net::Google::Spreadsheets->new(
    username => 'fill this in@gmail.com',
    password => 'fill this in too',
);

# iterate over the project codes in the %gkeys hash
foreach my $key ( keys %gkeys ) {
    # request the GoogleDocs spreadsheet corresponding
    # to the current key => value pair
    my $spreadsheet = $service->spreadsheet( {
        key => "$gkeys{$key}",
    } );

    # Each GoogleDocs spreadsheet contains one or more worksheets
    my @ws = $spreadsheet->worksheets;

    # iterate over the list of worksheet objects:
    foreach my $ws ( @ws ) {
        # print out the title of each worksheet in this spreadsheet
        print STDERR "Worksheet title: ", $ws->title(), "\n";
    } 

    # print the first worksheet TODO: pick the correct one to print using the worksheet title
    my $worksheet = $ws[0];

    # create an array where each array element contains the fields of a separate row in the worksheet
    my @rows = $worksheet->rows;

    # create a filehandle for printing the output
    open my ($FH), '>', $key . '_sheet1_'. $timestamp . '.txt' or die "Could not open file for writing: $!";

    # print out the "Real" header row first
    print $FH join("\t", @real_header), "\n";

    # my $content = $rows[0]->content();
    foreach my $row ( @rows ) {
        # this method call returns a hashref:
        my $content = $row->content();
        # here using a hash slice on the dereferenced hashref
        # to extract the values
        my @values = @{$content}{@header};
        # there may be lots of blank rows at the bottom that
        # we don't want to print
        next if $values[0] =~ m/^''/;
        print $FH join("\t", @values), "\n";
    } # close inner foreach loop
    close $FH;
} # close outer foreach loop

# print "\n", Data::Dumper->new([\$spreadsheet],[qw(spreadsheet)])->Indent(1)->Quotekeys(0)->Dump, "\n";

exit;

__END__

