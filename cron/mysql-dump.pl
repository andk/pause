#!/usr/bin/perl -w

use strict;

our $Id = q$Id$;

use lib "/home/k/PAUSE/lib";
use PAUSE ();
my @m=gmtime;
$m[5]+=1900;
$m[4]++;
my $D = sprintf "%04d%02d%02d%02d%02dGMT",@m[5,4,3,2,1];
my $BZIP = "/usr/local/bin/bzip2";
$BZIP = "/usr/bin/bzip2" unless -x $BZIP;
die "where is BZIP" unless -x $BZIP;

my $Struct = [
              {backupdir => "$PAUSE::Config->{FTPPUB}/PAUSE-data",
               cfg_dsn => "MOD_DATA_SOURCE_NAME",
               cfg_user => "MOD_DATA_SOURCE_USER",
               cfg_pw => "MOD_DATA_SOURCE_PW"},
];
for my $struct (@$Struct) {
  my $backup_dir = $struct->{backupdir};
  my($dbi,$dbengine,$db) = split /:/, $PAUSE::Config->{$struct->{cfg_dsn}};
  die "Script would not work for $dbengine" unless $dbengine =~ /mysql/i;
  my $user = $PAUSE::Config->{$struct->{cfg_user}};
  my $password = $PAUSE::Config->{$struct->{cfg_pw}};
  for my $var ($db,$user,$password) {
    die "illegal variable value[$val]" if $var =~ /['";]/;
  }
  system "/usr/local/bin/mysqldump --lock-tables --add-drop-table --user='$user' --password='$password' '$db' > $backup_dir/.moddump.current";
  rename "$backup_dir/.moddump.current", "$backup_dir/moddump.current";
  unlink "$backup_dir/moddump.current.bz2";
  system "$BZIP -9 --keep --small $backup_dir/moddump.current";
  system "/bin/cp $backup_dir/moddump.current.bz2 $backup_dir/moddump.$D.bz2";
}
