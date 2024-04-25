#!perl

use strict;
use warnings;

use Test::Requires qw(Test::mysqld);
use Test::Requires qw(File::Which);

BEGIN {
  unless (File::Which::which 'mysql') {
    Test::Builder->new->skip_all("no mysql found, needed for this test")
  }
}

use lib 't/lib';
use TestSetup;

use Test::Class::Load 't/test_classes/';

if (@ARGV) {
    Test::Class->runtests(@ARGV);
} else {
    Test::Class->runtests;
}

