#!/usr/bin/perl -w

use strict;
use lib "/home/k/PAUSE/lib";
use PAUSE;
use DBI;

my $user = shift @ARGV or die "Usage: $0 user";

my $db = DBI->connect(
		      $PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME},
		      $PAUSE::Config->{AUTHEN_DATA_SOURCE_USER},
		      $PAUSE::Config->{AUTHEN_DATA_SOURCE_PW},
		      {RaiseError => 1}
		     );
my $sth = $db->prepare(qq{SELECT password FROM usertable WHERE user=?});
my $ret = $sth->execute(uc $user);

die "User '$user' not found" unless $sth->rows > 0;
die "Panic: more than one user '$user'" if $sth->rows > 1;

my($passwd) = $sth->fetchrow_array;
$sth->finish;
$db->disconnect;

my @system = ("adduser", "-p", $passwd, lc $user);
$ret = system @system;

die "adduser returned bad status: '$ret'" if $ret;
