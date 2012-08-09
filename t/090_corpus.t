#!perl

use strict;
use warnings;
use Test::More;
use Test::Differences;
use JSON::XS;
use File::Find::Rule;
use File::Slurp qw/read_file/;
use Getopt::Opinionated;
use Data::Printer;

my @tests = File::Find::Rule
    ->file()
    ->name( '*.json' )
    ->in( 't/json/' );

for my $test ( @tests ) {
    note "Test file: $test";
    my @cases = @{ decode_json read_file $test };
    for my $case ( @cases ) {

        my $atom = 'Getopt::Opinionated';
        for my $setup ( @{ $case->{'setup'} } ) {
            my ( $method, $options ) = @$setup;
            $atom = $atom->$method( $options );
        }

        my $result = $atom->args_from( $case->{'cmdline'} )->parse();

        is_deeply( $result, $case->{'expected'}, $case->{'name'} );

    }

}

done_testing;