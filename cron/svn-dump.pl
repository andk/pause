#!/usr/bin/perl -w


=pod

Check current version out in a temporary directory, make a tarball.

And make an svn dump as a backup while we are at it.

Remove oldest files from the target directory at the end.

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

my $system = "$PAUSE::Config->{SVNBIN}/svn co file://$repopath/trunk pause-wc |";
my $revision;
my $job;
open $job, $system or die;
while (<$job>) {
  $revision = $1 if /Checked out revision (\d+)/;
}
close $job;
die "No revision?" unless $revision;
unless (-e "$DIR/pause-wc-$revision.tar.bz2"){
  rename "pause-wc", "pause-wc-$revision" or die "Could not rename: $!";

  $system = "tar cjf pause-wc-$revision.tar.bz2 pause-wc-$revision";
  system($system)==0 or die "Could not svn co";

  # warn "pause-wc-$revision.tar.bz2 -> $DIR/pause-wc-$revision.tar.bz2";
  copy "pause-wc-$revision.tar.bz2", "$DIR/pause-wc-$revision.tar.bz2" or die;
}

my $dout = "svn.dump";
my $derr = "svn.err";

$system = "$PAUSE::Config->{SVNBIN}/svnadmin dump $repopath > $dout 2> $derr";
system($system)==0 or die "Could not svnadmin";

open my $fh, $derr or die "Could not open $derr";
$revision = "";
while (<$fh>) {
  $revision = $1 if /Dumped revision (\d+)/;
}
close $fh;
die "No revision?" unless $revision;
unless (-e "$DIR/pause-svndump-$revision.bz2"){
  $system = "bzip2 -9 $dout";
  system($system)==0 or die "Could not bzip2";

  # warn "$dout.bz2 -> $DIR/pause-svndump-$revision.bz2";
  copy "$dout.bz2", "$DIR/pause-svndump-$revision.bz2" or die;
}

opendir DIR, $DIR or die;
my @readdir = grep /^pause/, readdir DIR;
my @sorted = map { $_->[0] }
    sort { $a->[1] <=> $b->[1] }
    map { [ "$DIR/$_", -M "$DIR/$_" ] }
    @readdir;
while (@sorted > 12) {
  my $dele = pop @sorted;
  unlink $dele or die;
}
