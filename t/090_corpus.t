#!perl

use strict;
use warnings;
use Test::More;
use Test::Differences;
use Test::Exception;
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

        # Test for an exception...
        if ( my $exception = $case->{'dies'} || $case->{'fails'} ) {
            my $exception_re = qr/$exception/;
            throws_ok {
                run_case( $atom, $case );
            } $exception_re, $case->{'name'};

        # Test for result
        } else {
            my $result = run_case( $atom, $case );
            is_deeply( $result, $case->{'expected'}, $case->{'name'} );
        }

    }

}

sub run_case {
    my ($atom, $case) = @_;
    for my $setup ( @{ $case->{'setup'} } ) {
        my ( $method, $options ) = @$setup;
        $atom = $atom->$method( $options );
    }
    return $atom->args_from( $case->{'cmdline'} )->parse(
        ( $case->{'parse'} ? (sub {$case->{'parse'}}) : () )
    );
}

done_testing;