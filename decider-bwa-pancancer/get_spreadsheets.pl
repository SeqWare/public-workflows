#!/usr/bin/perl
# File: get_spreadsheets.pl by Marc Perry
#
# Concept: I would like to create a command line tool
# that will let me quickly download a GDocs spreadsheet
#
# Last Updated: 2014-05-14, Status: basic functionality working

use strict;
use warnings;
use Net::Google::Spreadsheets;
use DateTime;
use DateTime::Duration;
use Getopt::Long;
use Data::Dumper;
use Carp qw( verbose );

# globally overriding calls to die, and sending them to Carp
$SIG{__DIE__} = sub { &Carp::confess };

my $username = q{};
my $password = q{};

# The actual column header fields in the first row of all of these spreadsheets:
my @real_header = ( 'Study', 'dcc_project_code', 'Accession Identifier', 'submitter_donor_id', 'submitter_specimen_id', 'submitter_sample_id', 'Readgroup SM UUID', 'dcc_specimen_type', 'Normal/Tumor Designation', 'Matching Normal or Tumour ICGC Sample Identifier', 'Sequencing Strategy', 'Number of BAM files/sample', 'Target Upload Date (DD/MM/YYYY)', 'Actual Upload Date (DD/MM/YYYY)', );

# The mangled column header fields created when Net::Google::Spreadsheets parses the GoogleDocs:
my @header = ( 'study', 'dccprojectcode', 'accessionidentifier', 'submitterdonorid', 'submitterspecimenid', 'submittersampleid', 'readgroupsmuuid', 'dccspecimentype', 'normaltumordesignation', 'matchingnormalortumouricgcsampleidentifier', 'sequencingstrategy', 'numberofbamfilessample', 'targetuploaddateddmmyyyy', 'actualuploaddateddmmyyyy', );

my %projects = ( 'BRCA-EU' => { key => '0AoQ6zq-rG38-dDhvU0VZNk4wMGpDUk1NaWZHMG5LLWc',
                             title => 'Sheet1',
                           },
              'BRCA-UK' => { key => '0ApWzavEDzSJddDAzdjVPbVVubHV6UDgxSEcxa0F3bEE',
                             title => 'BRCA-UK PanCancer Data',
                           },
              'BTCA-SG' => { key => '0ApWzavEDzSJddGhFak1rZEJmUHFjOWR3MTRPVndrVlE',
                             title => 'BTCA-SG PanCancer Data',
                           },
              'CLLE-ES' => { key => '0ApWzavEDzSJddFlnVTNmVXA5dWFNWlBhbVlpTFdWTlE',
                             title => 'CLLE-ES PanCancer Data',
                           },
              'EOPC-DE' => { key => '0ApWzavEDzSJddEUtMUdHTFlrajA5Y0poQmFqTVdpY3c',
                             title => 'EOPC-DE PanCancer Data',
                           },
              'ESAD-UK' => { key => '0ApWzavEDzSJddENiS3F2V1BIU3diVGpRd3hPeHkyWXc',
                             title => 'ESAD-UK PanCancer Data',
                           },
              'LAML-KR' => { key => '0ApWzavEDzSJddEJfUVJ2TEd0aGJJazM3RktXVmtGX1E',
                             title => 'LAML-KR PanCancer Data',
                           },
              'LIRI-JP' => { key => '0ApWzavEDzSJddExGbTZfSG1HZmZJTEUxVjN0NzZNNlE',
                             title => 'LIRI-JP PanCancer Data',
                            },
              'MALY-DE' => { key => '0ApWzavEDzSJddFdLWlJ3YkxoMzA4TnB4QXhkQ0VuWVE',
                             title => 'MALY-DE PanCancer Data',
                           },
              'PACA-CA' => { key => '0ApWzavEDzSJddF9BUXpLa0Qzd0JJRXJZWllmV2V6Wnc',
                             title => 'OICR PanCancer Data - new sheet for SOP 1.0',
                           },
              'PBCA-DE' => { key => '0ApWzavEDzSJddDAyT2x1WmQ5dkl0NENnVTdPSXBLRXc',
                             title => 'PBCA-DE PanCancer Data',
                           },
              'PRAD-UK' => { key => '0ApWzavEDzSJddEZ6aUdVMnVoX1FEdVZ2REswY3pVMGc',
                             title => 'PRAD-UK PanCancer Data',
                           },
              'LICA-FR' => { key => '0ApWzavEDzSJddFctcDhqajNtWVM5aWxzQzByTzl2MEE',
                             title => 'LICA-FR PanCancer Data',
                           },
              'ORCA-IN' => { key => '0ApWzavEDzSJddEdwaHBVdlJqMlVfYjd5SFRqek9PbHc',
                             title => 'ORCA-IN PanCancer Data',
                           },
              'OV-AU'   => { key => '0ApWzavEDzSJddFBieGxUQ204dGdzLVg0T3Zfb1NXNnc',
                             title => 'OV-AU PanCancer Data',
                           },
              'GACA-CN' => { key => '0ApWzavEDzSJddFBNZmJtREV2eG1ybkZCZ2FoV1g2T3c',
                             title => 'GACA-CN PanCancer Data',
                           },
);

my $usage = "USAGE: '$0 --user <your.address\@gmail.com> --pass <your GMail password>'\n\n";

GetOptions("user=s" => \$username, "pass=s" => \$password, );

die "$usage" unless ( $username and $password );

my @now = localtime();
my $timestamp = sprintf("%04d_%02d_%02d_%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1]);

# Create a new Net::Google::Spreadsheets object:
my $service = Net::Google::Spreadsheets->new(
    username => "$username",
    password => "$password",
);

# iterate over the project codes in the %projects hash
foreach my $proj ( keys %projects ) {
    # request the GoogleDocs spreadsheet corresponding
    # to the current key => value pair
    my $spreadsheet = $service->spreadsheet( {
        key => "$projects{$proj}->{key}",
    } );

    # Each GoogleDocs spreadsheet contains one or more worksheets
    my @ws = $spreadsheet->worksheets;

    # iterate over the list of worksheet objects:
    # foreach my $ws ( @ws ) {
        # print out the title of each worksheet in this spreadsheet
        # print STDERR "Worksheet title: ", $ws->title(), "\n";
    # } 

    # iterate over the list of worksheet objects
    foreach my $worksheet ( @ws ) {
        # just pick the one worksheet that matches the desired
        # worksheet title
        if ( $worksheet->title() eq $projects{$proj}->{title} ) {
            print STDERR "Processing the worksheet for project: $proj\n";
            # create an array where each array element contains the fields of a separate row in the worksheet
            my @rows = $worksheet->rows;
            # create a filehandle for printing the output
            open my ($FH), '>', $proj . '_sheet1_'. $timestamp . '.txt' or die "Could not open file for writing: $!";

            # print out the "Real" header row first
            print $FH join("\t", @real_header), "\n";
            foreach my $row ( @rows ) {
                # this method call returns a hashref:
                my $content = $row->content();
                # here using a hash slice on the dereferenced hashref
                # to extract the values
                my @values = @{$content}{@header};
                # there may be lots of blank rows at the bottom that
                # we don't want to print
                next if $values[0] =~ m/^(''|\#N\/A)/;
                print $FH join("\t", @values), "\n";
            } # close inner foreach loop
            close $FH;
        }
        else {
            next;
        } # close if/else test
    } # close foreach loop
} # close outer foreach loop

# print "\n", Data::Dumper->new([\$spreadsheet],[qw(spreadsheet)])->Indent(1)->Quotekeys(0)->Dump, "\n";

exit;

__END__

