#!perl

use strict;
use warnings;

use Test::Requires qw(Test::mysqld);

BEGIN {
  unless (-e '/usr/local/mysql/bin/mysql') {
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

