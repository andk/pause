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

my $Rev = q$Rev$;
print "$Rev\n";

my $sharp = 1;

my $db = DBI->connect(
                      $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
                      $PAUSE::Config->{MOD_DATA_SOURCE_USER},
                      $PAUSE::Config->{MOD_DATA_SOURCE_PW},
                      {RaiseError => 0}
                     );

my $U = $db->selectall_hashref("SELECT userid,ustatus FROM users","userid");
my $sth = $db->prepare("UPDATE users SET ustatus='active', ustatus_ch=NOW() WHERE userid=?");

my $backpan = "/home/ftp/pub/backpan/authors/id";
opendir my $dh, $backpan or die $!;
for my $de1 (readdir $dh) {
  next if $de1 =~ /^\.\.?$/;
  die "Illegal directory $backpan/$de1" unless $de1=~/^[A-Z]$/;
  opendir my $dh2, "$backpan/$de1" or die $!;
  for my $de2 (readdir $dh2) {
    next if $de2 =~ /^\.\.?$/;
    die "Illegal directory $backpan/$de1/$de2" unless $de2=~/^[A-Z][-A-Z]$/;
    opendir my $dh3, "$backpan/$de1/$de2" or die $!;
    for my $de3 (readdir $dh3) {
      next if $de3 =~ /^\.\.?$/;
      die "Illegal directory $backpan/$de1/$de2/$de3" unless $de3=~/^[A-Z][-A-Z]*[A-Z]$/;
      die "Illegal userdirectory $de3" unless $U->{$de3};
      die "Deleted userdirectory $de3" if $U->{$de3}{ustatus} eq 'delete';
      next if $U->{$de3}{ustatus} eq 'active';
      print "Setting $de3 to active\n";
      $sth->execute($de3);
    }
  }
}
