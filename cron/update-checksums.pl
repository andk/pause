#!/usr/bin/perl -w

use CPAN::Checksums 1.016;
use File::Find;
use strict;
use vars qw($DEBUG);

use lib "/home/k/PAUSE/lib";
use PAUSE ();

my $root = $PAUSE::Config->{MLROOT};

my $max = 100; # 15 was really slow
my $cnt = 0;

$CPAN::Checksums::CAUTION = 1;
$CPAN::Checksums::SIGNING_PROGRAM =
    $PAUSE::Config->{CHECKSUMS_SIGNING_PROGRAM};
$CPAN::Checksums::SIGNING_KEY =
    $PAUSE::Config->{CHECKSUMS_SIGNING_KEY};

find(sub {
       return if $cnt>=$max;
       return unless $File::Find::name =~ m|id/.|;
       return if -l;
       return unless -d;
       local($_); # Ouch, has it bitten that the following function
                  # did something with $_. Must have been a bug in 5.00556???

       # we need a way to force updatedir to run an update. If the
       # signature needs to be replaced for some reason. I do not know
       # which reason this will be, but it may happen. Something like
       # $CPAN::Checksums::FORCE_UPDATE?

       my $ret = CPAN::Checksums::updatedir($File::Find::name);
       return if $ret == 1;
       warn "name[$File::Find::name]\n" if $DEBUG;
       $cnt++;
     }, $root);

