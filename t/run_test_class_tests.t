#!perl

use strict;
use warnings;

use lib 'lib';
use lib 't/lib/';

use Test::Class::Load 't/test_classes/';

if (@ARGV) {
    Test::Class->runtests(@ARGV);
} else {
    Test::Class->runtests;
}

