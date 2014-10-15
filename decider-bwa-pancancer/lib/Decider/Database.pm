package Decider::Database;

use common::sense;
use autodie qw(:all);

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Data::Dumper;

use JSON;

use BerkeleyDB;
use base 'BerkeleyDB::Hash';

sub failed_connect {
    my ($class) = @_;

    my $filename = "$Bin/../database/failed.db";

    my $failed_db = db_connect($class,$filename);
   
    return bless $failed_db, $class;
}

sub completed_connect {
    my ($class) = @_;

    my $filename = "$Bin/../database/completed.db";

    my $completed_db = db_connect($filename);

    return $completed_db;
}

sub db_connect {
    my ($class, $filename) = @_;

    return $class->SUPER::new(
              -Filename => $filename,
              -Flags    => DB_CREATE);
}


sub add_sample {
   my ($class, $sample_id, $date) = @_;

   my ($stored_value, $new_value);
   if ($stored_value = get_sample($class, $sample_id)) {
       my @stored_dates = @{$stored_value};
       #check if date is already in database
       unless ($date ~~ @stored_dates) {
           push @stored_dates, $date;
       }
       $new_value = \@stored_dates;
   }
   else {
       $new_value = [$date];
   }

   $class->db_put($sample_id, encode_json($new_value));
}

sub get_sample {
   my ($class, $sample_id) = @_;

   my $value_json;
   $class->db_get($sample_id, $value_json);
   
   return (defined $value_json)? decode_json($value_json): undef;
}

sub get_all_sample {
   my ($class) = @_;

   my ($key, $value, %data);
   my $cursor = $class->db_cursor();
   while ($cursor->c_get($key, $value, DB_NEXT) == 0) {
       $data{$key} = $value;
   }

   return \%data;
}




1;
