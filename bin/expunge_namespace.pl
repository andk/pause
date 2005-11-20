#!/usr/local/bin/perl -w

=pod

What happes when lifecycle is delete? Maybe this script should be executed?

Frankly, I have not done research if this is already implemented
elsewhere, but I check it in as a placeholder.

=cut

use strict;
use lib "/home/k/PAUSE/lib";
use PAUSE;
use DBI;

my $dbm = DBI->connect(
		       $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
		       $PAUSE::Config->{MOD_DATA_SOURCE_USER},
		       $PAUSE::Config->{MOD_DATA_SOURCE_PW},
		       {RaiseError => 1}
		      );

my $rpkg = shift or die "Usage: $0 packagename";

my $sth0 = $dbm->prepare(qq{SELECT * FROM mods    WHERE modid=?});
my $sth1 = $dbm->prepare(qq{DELETE FROM mods      WHERE modid=?});
my $sth2 = $dbm->prepare(qq{DELETE FROM packages  WHERE package=?});
my $sth3 = $dbm->prepare(qq{DELETE FROM perms     WHERE package=? and userid=?});
my $sth4 = $dbm->prepare(qq{DELETE FROM primeur   WHERE package=? and userid=?});
my $sth5 = $dbm->prepare(qq{SELECT * FROM perms   WHERE package=?});
my $sth6 = $dbm->prepare(qq{SELECT * FROM primeur WHERE package=?});

die "XXX not yet implemented";
# Determine owner and use it for 3 and 4, at the end warn about
# remaning pers and primeur records


$sth0->execute;
