#!/usr/bin/perl

die "
# since we are switching to use /etc/cron.d/pause2016 for the core
# pause stuff and puppet for OS and NOC level things, we believe, this
# file is obsolete";

use File::Basename ();
use File::Compare ();
use File::Copy ();
use File::Temp ();

my($fh, $CRONTMP) = File::Temp::tempfile("$0-tmpXXXX");
my $CRONREPO=File::Basename::dirname __FILE__;
$CRONREPO.="/CRONTAB.ROOT";

0==system "crontab -u root -l > $CRONTMP" or die "Could not execute crontab";

if (File::Compare::compare $CRONTMP, $CRONREPO){
    File::Copy::cp $CRONTMP, $CRONREPO;
    chmod 0644, $CRONREPO;
}
unlink $CRONTMP;
