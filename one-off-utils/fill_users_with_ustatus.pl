#!/usr/bin/perl -w

=pod

We just added two fields to table users:

  ustatus enum('unused','active','delete') NOT NULL default 'unused',
  ustatus_ch datetime NOT NULL default '0000-00-00 00:00:00',

Now we must see the backpan and change ustatus to active for all
existing directories userdirectories.

In mldistwatch, too, we must check for new userdirectories and mark
them.

=cut

use strict;
use lib "/home/k/PAUSE/lib";
use PAUSE;
use DBI;

my $Rev = q$Revision: 1.2 $;

print "$Rev\n";

my $sharp = 1;

my $db = DBI->connect(
                      $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
                      $PAUSE::Config->{MOD_DATA_SOURCE_USER},
                      $PAUSE::Config->{MOD_DATA_SOURCE_PW},
                      {RaiseError => 0}
                     );

my $U = $db->selectall_hashref("SELECT userid FROM users WHERE ustatus='unused'","userid");
my $sth = $db->prepare("UPDATE users SET ustatus='active', ustatus_ch=NOW() WHERE userid=?");

my $backpan = "/home/ftp/pub/backpan/authors/id";
opendir my $dh, $backpan or die $!;
for my $de1 (readdir $dh) {
  next unless $de1=~/^[A-Z]$/;
  opendir my $dh2 = "$backpan/$de1";
  for my $de2 (readdir $dh2) {
    next unless $de2=~/^[A-Z]\w$/;
    opendir my $dh3 = "$backpan/$de1/$de2";
    for my $de3 (readdir $dh3) {
      next unless $de3=~/^[A-Z]\w$/;
      $sth->execute($de3);
    }
  }
}
