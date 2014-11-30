#!perl

use strict;
use warnings;

use lib 't/lib';
use TestSetup;

use Test::Aggregate;

my $tests = Test::Aggregate->new( { dirs => 't/web_tests', } );
$tests->run;
