#!/usr/bin/perl -w


=pod

Write an svn dump, check that same version out in a temporary
directory, make a tarball of that.

=cut

use strict;
use lib "/home/k/PAUSE/lib";
use PAUSE;
use File::Temp;
use File::Copy qw(copy);


my $DIR = "$PAUSE::Config->{FTPPUB}/PAUSE-data";
unless (-d $DIR) {
  require File::Path;
  File::Path::mkpath $DIR;
}

my $tdir = File::Temp::tempdir("TEMP-XXXXXX", DIR => "/tmp", CLEANUP=>1);
chdir $tdir or die "Could not chdir to $tdir: $!";

my @m=gmtime;
$m[5]+=1900;
$m[4]++;
my $D = sprintf "%04d%02d%02d%02d%02dGMT",@m[5,4,3,2,1];

my($repopath) = $PAUSE::Config->{SVNPATH};

my $dout = "svn.dump";
my $derr = "svn.err";

my $system = "$PAUSE::Config->{SVNBIN}/svnadmin dump $repopath > $dout 2> $derr";
system($system)==0 or die "Could not svnadmin";

open my $fh, $derr or die "Could not open $derr";
my $revision;
while (<$fh>) {
  $revision = $1 if /Dumped revision (\d+)/;
}

$system = "$PAUSE::Config->{SVNBIN}/svn co file://$repopath pause-wc-$revision";
system($system)==0 or die "Could not svn co";

$system = "tar cjf pause-wc-$revision.tar.bz2 pause-wc-$revision";
system($system)==0 or die "Could not svn co";

$system = "bzip2 -9 $dout";
system($system)==0 or die "Could not bzip2";

warn "$dout.bz2 -> $DIR/pause-svndump-$revision.bz2";
copy "$dout.bz2", "$DIR/pause-svndump-$revision.bz2" or die
    unless -e "$DIR/pause-svndump-$revision.bz2";

warn "pause-wc-$revision.tar.bz2 -> $DIR/pause-wc-$revision.tar.bz2";
copy "pause-wc-$revision.tar.bz2", "$DIR/pause-wc-$revision.tar.bz2" or die
    unless -e "$DIR/pause-wc-$revision.tar.bz2";

