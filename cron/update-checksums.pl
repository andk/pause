#!/usr/local/bin/perl -w

use CPAN::Checksums 1.018;
use File::Copy qw(cp);
use File::Find;
use strict;

use lib "/home/k/PAUSE/lib";
use PAUSE ();

use Getopt::Long;
our %Opt;
GetOptions(\%Opt,
           "max=i",
           "debug!",
          ) or die;
$Opt{debug} ||= 0;
my $root = $PAUSE::Config->{MLROOT};

# max: 15 was really slow, 100 is fine, 1000 was necessary recently
# because of key-expiration on 2005-02-02
$Opt{max} ||= 100;

my $cnt = 0;

$CPAN::Checksums::CAUTION = 1;
$CPAN::Checksums::SIGNING_PROGRAM =
    $PAUSE::Config->{CHECKSUMS_SIGNING_PROGRAM};
$CPAN::Checksums::SIGNING_KEY =
    $PAUSE::Config->{CHECKSUMS_SIGNING_KEY};
$CPAN::Checksums::MIN_MTIME_CHECKSUMS =
    $PAUSE::Config->{MIN_MTIME_CHECKSUMS} || 0;

find(sub {
       return if $cnt>=$Opt{max};
       return unless $File::Find::name =~ m|id/.|;
       return if -l;
       return unless -d;
       local($_); # Ouch, has it bitten that the following function
                  # did something with $_. Must have been a bug in 5.00556???

       # we need a way to force updatedir to run an update. If the
       # signature needs to be replaced for some reason. I do not know
       # which reason this will be, but it may happen. Something like
       # $CPAN::Checksums::FORCE_UPDATE?

       cp "$File::Find::name/CHECKSUMS", "$File::Find::name/CHECKSUMS.bak" or die $! if $Opt{debug};
       my $ret = CPAN::Checksums::updatedir($File::Find::name);
       return if $ret == 1;
       warn "name[$File::Find::name]\n" if $Opt{debug};
       $cnt++;
     }, $root);

