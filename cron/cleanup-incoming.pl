#!/usr/bin/perl

my $Id = q$Id$;

use lib "/home/k/PAUSE/lib";
use PAUSE ();
use DBI;

my $incdir = $PAUSE::Config->{INCOMING_LOC};

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
  my $absdirent = "$incdir/$dirent";
  next if -M $absdirent < 1/24;
  $sth->execute($dirent);
  next if $sth->rows > 0;
  warn "Should unlink $absdirent";
}
