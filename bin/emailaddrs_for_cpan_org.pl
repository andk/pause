#!/usr/bin/perl -w

use strict;
use lib "/home/k/PAUSE/lib";
use PAUSE;
use DBI;

use vars qw(%ALL);

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

my $sth1 = $dbm->prepare(qq{SELECT userid, email
                            FROM   users
                            WHERE  isa_list = ''
                              AND  (
                                    cpan_mail_alias='publ'
                                    OR
                                    cpan_mail_alias='secr'
                                   )});
$sth1->execute;
while (my($id,$mail) = $sth1->fetchrow_array) {
  $ALL{$id} = $mail; # we store public email even for those who want
                     # secret, because we never know if we will find a
                     # secret one
}
$sth1->finish;
my $sth2 = $dbm->prepare(qq{SELECT userid
                            FROM   users
                            WHERE  cpan_mail_alias='secr'
                              AND  isa_list = ''});
$sth2->execute;
my $sth3 = $dba->prepare(qq{SELECT secretemail
                            FROM   usertable
                            WHERE  user=?});
while (my($id) = $sth2->fetchrow_array) {
  $sth3->execute($id);
  next unless $sth3->rows;
  my($mail) = $sth3->fetchrow_array or next;
  $ALL{$id} = $mail;
}
$sth2->finish;
$sth3->finish;
$dba->disconnect;
$dbm->disconnect;

while (my($id,$mail) = each %ALL) {
  print "$id\t$mail\n";
}

