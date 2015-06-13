#!perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'App::DVCS::Digest' ) || print "Bail out!\n";
}

diag( "Testing App::DVCS::Digest $App::DVCS::Digest::VERSION, Perl $], $^X" );
