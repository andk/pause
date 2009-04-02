#!/usr/local/bin/perl -w


die "deprecated since we are in git";

=pod

Check current version out in a temporary directory, make a tarball.

And make an svn dump as a backup while we are at it.

Remove oldest files from the target directory at the end.

KNOWN BUG: We must not run svndump as root, we might cause libdb to
           create a new logfile which would prevent that the user SVN
           can append to that file. The solution would be to drop
           privileges before calling svndump and to chown the
           directories that are needed after the svndump to be owned
           by SVN.

=cut

use strict;
use lib "/home/k/PAUSE/lib";
use PAUSE;
use File::Temp;
use File::Copy qw(copy);

for my $repo (qw(pause cpanpm)) {
  my $ucrepo = uc $repo;
  my $DIR = "$PAUSE::Config->{FTPPUB}/$ucrepo-code";
  unless (-d $DIR) {
    require File::Path;
    File::Path::mkpath $DIR;
  }

  my $tdir = File::Temp::tempdir("TEMP-XXXXXX", DIR => "/tmp", CLEANUP=>1);
  chdir $tdir or die "Could not chdir to $tdir: $!";

  my($repopath) = "$PAUSE::Config->{SVNPATH}/$repo";

  my $system = "$PAUSE::Config->{SVNBIN}/svn co file://$repopath/trunk $repo-wc |";
  my $revision;
  my $job;
  open $job, $system or die;
  while (<$job>) {
    $revision = $1 if /Checked out revision (\d+)/;
  }
  close $job;
  die "No revision?" unless $revision;
  unless (-e "$DIR/$repo-wc-$revision.tar.bz2"){
    rename "$repo-wc", "$repo-wc-$revision" or die "Could not rename: $!";

    $system = "tar cjf $repo-wc-$revision.tar.bz2 $repo-wc-$revision";
    system($system)==0 or die "Could not svn co";

    # warn "$repo-wc-$revision.tar.bz2 -> $DIR/$repo-wc-$revision.tar.bz2";
    copy "$repo-wc-$revision.tar.bz2", "$DIR/$repo-wc-$revision.tar.bz2" or die;
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
  unless (-e "$DIR/$repo-svndump-$revision.bz2"){
    $system = "bzip2 -9 $dout";
    system($system)==0 or die "Could not bzip2";

    # warn "$dout.bz2 -> $DIR/$repo-svndump-$revision.bz2";
    copy "$dout.bz2", "$DIR/$repo-svndump-$revision.bz2" or die;
  }

  opendir DIR, $DIR or die;
  my @readdir = grep /^\Q$repo\E/, readdir DIR;
  my @sorted = map { $_->[0] }
      sort { $a->[1] <=> $b->[1] }
          map { [ "$DIR/$_", -M "$DIR/$_" ] }
              @readdir;
  while (@sorted > 12) {
    my $dele = pop @sorted;
    unlink $dele or die;
  }
}
