#!/usr/bin/perl -w

use strict;
use lib "/home/k/PAUSE/lib";
use PAUSE;
use DBI;

my $dba = DBI->connect(
		       $PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME},
		       $PAUSE::Config->{AUTHEN_DATA_SOURCE_USER},
		       $PAUSE::Config->{AUTHEN_DATA_SOURCE_PW},
		       {RaiseError => 1}
		      );
my $dbm = DBI->connect(
		       $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
		       $PAUSE::Config->{MOD_DATA_SOURCE_USER},
		       $PAUSE::Config->{MOD_DATA_SOURCE_PW},
		       {RaiseError => 1}
		      );

my $sth1 = $dbm->prepare(qq{SELECT userid FORM users WHERE ustatus='delete'});
$sth1->execute;
while (my($id) = $sth1->fetchrow_array) {
  warn "XXX not yet implemented: delete $id";
  # check if user-directory is really empty
  # check if the user is in both users and usertable
  # delete from usertable
  # delete from users
}
