#!/usr/bin/perl -w


=pod

Check current version out in a temporary directory, make a tarball.

=cut

use strict;
use lib "/home/k/PAUSE/lib";
use PAUSE;
use File::Temp;
use File::Copy qw(copy);


my $DIR = "$PAUSE::Config->{FTPPUB}/PAUSE-code";
unless (-d $DIR) {
  require File::Path;
  File::Path::mkpath $DIR;
}

my $tdir = File::Temp::tempdir("TEMP-XXXXXX", DIR => "/tmp", CLEANUP=>1);
chdir $tdir or die "Could not chdir to $tdir: $!";

my($repopath) = $PAUSE::Config->{SVNPATH};

$system = "$PAUSE::Config->{SVNBIN}/svn co file://$repopath pause-wc |";
my $revision;
open my $job, $system or die;
while (<$job>) {
  $revision = $1 if /Checked out revision (\d+)/;
}
die "No revision?" unless $revision;
rename "pause-wc", "pause-wc-$revision" or die "Could not rename: $!";

$system = "tar cjf pause-wc-$revision.tar.bz2 pause-wc-$revision";
system($system)==0 or die "Could not svn co";

# warn "pause-wc-$revision.tar.bz2 -> $DIR/pause-wc-$revision.tar.bz2";
copy "pause-wc-$revision.tar.bz2", "$DIR/pause-wc-$revision.tar.bz2" or die
    unless -e "$DIR/pause-wc-$revision.tar.bz2";

