#!/usr/bin/perl

my $Id = q$Id$;

use lib "/home/k/PAUSE/lib";
use PAUSE ();
use DBI;
use File::Spec;

my $incdir = File::Spec->canonpath($PAUSE::Config->{INCOMING_LOC});

my $dbh = DBI->connect(
                       $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
                       $PAUSE::Config->{MOD_DATA_SOURCE_USER},
                       $PAUSE::Config->{MOD_DATA_SOURCE_PW},
                       { RaiseError => 1 }
                      );

my $sth = $dbh->prepare("SELECT * FROM uris where uri=?");

opendir DIR, $incdir or die;
for my $dirent (readdir DIR) {
  next if $dirent =~ /^\.(|\.|message)\z/;
  my $absdirent = File::Spec->catfile($incdir,$dirent);
  next unless -f $absdirent;
  next if -M $absdirent < 1/24;
  $sth->execute($dirent);
  next if $sth->rows > 0;
  unlink $absdirent or die "Could not unlink $absdirent: $!";
  warn "unlinked $absdirent\n";
}
closedir DIR;
