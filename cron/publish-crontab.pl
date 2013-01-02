#!/usr/bin/perl

use File::Basename ();
use File::Compare ();
use File::Copy ();
use File::Temp ();

my $CRONTMP = File::Temp::tempfile("$0-tmpXXXX", CLEANUP => 1) ;
my $CRONREPO=File::Basename::dirname __FILE__;
$CRONREPO.="/CRONTAB.ROOT";

0==system "crontab -u root -l > $CRONTMP" or die "Could not execute crontab";

if (File::Compare::compare $CRONTMP, $CRONREPO){
    File::Copy::cp $CRONTMP, $CRONREPO;
    chmod 0644, $CRONREPO;
}
