#!/usr/local/bin/perl -w

use CPAN::Checksums 1.018;
use File::Find;
use strict;
use vars qw($DEBUG);

use lib "/home/k/PAUSE/lib";
use PAUSE ();

my $root = $PAUSE::Config->{MLROOT};

my $max = 1000; # 15 was really slow, 100 is fine, 1000 is necessary now because of expiration on 2005-02-02
my $cnt = 0;

$CPAN::Checksums::CAUTION = 1;
$CPAN::Checksums::SIGNING_PROGRAM =
    $PAUSE::Config->{CHECKSUMS_SIGNING_PROGRAM};
$CPAN::Checksums::SIGNING_KEY =
    $PAUSE::Config->{CHECKSUMS_SIGNING_KEY};
$CPAN::Checksums::MIN_MTIME_CHECKSUMS =
    $PAUSE::Config->{MIN_MTIME_CHECKSUMS} || 0;

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

