#!/usr/bin/perl -w

use CPAN::Checksums;
use File::Find;
use strict;
use vars qw($DEBUG);

use lib "/home/k/PAUSE/lib";
use PAUSE ();

my $root = $PAUSE::Config->{MLROOT};

my $max = 15;
my $cnt = 0;
$CPAN::Checksums::CAUTION = 1;
find(sub {
       return if $cnt>=$max;
       return unless $File::Find::name =~ m|id/.|;
       return if -l;
       return unless -d;
       local($_); # Ouch, has it bitten that the following function
                  # did something with $_. Must have been a bug in 5.00556???
       my $ret = CPAN::Checksums::updatedir($File::Find::name);
       return if $ret == 1;
       warn "name[$File::Find::name]\n" if $DEBUG;
       $cnt++;
}, $root);

