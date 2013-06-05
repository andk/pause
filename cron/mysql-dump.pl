#!/usr/local/bin/perl -w

=pod

Before extended-insert:

-rw-r--r--  1 root root 39114962 Jan  6 15:47 moddump.current
-rw-r--r--  1 root root  7031636 Jan  6 15:47 moddump.200801061447GMT.bz2

After extended-insert:

-rw-r--r--  1 root root 50195254 Jan  6 17:47 moddump.current
-rw-r--r--  1 root root  7203437 Jan  6 17:47 moddump.200801061647GMT.bz2

=cut

use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";
use PAUSE ();
my @m=gmtime;
$m[5]+=1900;
$m[4]++;
my $D = sprintf "%04d%02d%02d%02d%02dGMT",@m[5,4,3,2,1];
my $BZIP = $PAUSE::Config->{BZIP2_PATH};
die "where is BZIP" unless -x $BZIP;
use File::Path ();
use File::Basename ();

my $Struct = [
              {backupdir => "$PAUSE::Config->{FTPPUB}/PAUSE-data",
               cfg_dsn => "MOD_DATA_SOURCE_NAME",
               cfg_user => "MOD_DATA_SOURCE_USER",
               cfg_pw => "MOD_DATA_SOURCE_PW",
               master => 1,
              },
              {backupdir => $PAUSE::Config->{AUTHEN_BACKUP_DIR},
               cfg_dsn => "AUTHEN_DATA_SOURCE_NAME",
               cfg_user => "AUTHEN_DATA_SOURCE_USER",
               cfg_pw => "AUTHEN_DATA_SOURCE_PW",
              },
];
for my $struct (@$Struct) {
  my $backup_dir = $struct->{backupdir};
  File::Path::mkpath $backup_dir;
  my($dbi,$dbengine,$db) = split /:/, $PAUSE::Config->{$struct->{cfg_dsn}};
  die "Script would not work for $dbengine" unless $dbengine =~ /mysql/i;
  my $user = $PAUSE::Config->{$struct->{cfg_user}};
  my $password = $PAUSE::Config->{$struct->{cfg_pw}};
  for my $var ($db,$user,$password) {
    die "suspicious variable var[$var]" if $var =~ /[\'\"\;]/;
  }
  my $master_data = "";
  if ($struct->{master}) {
    $master_data = " --master-data";
  }
  system "mysqldump$master_data --lock-tables --add-drop-table --user='$user' --password='$password' '--extended-insert=0' '$db' > $backup_dir/.${db}dump.current";
  rename "$backup_dir/.${db}dump.current", "$backup_dir/${db}dump.current";
  unlink "$backup_dir/${db}dump.current.bz2";
  system "$BZIP -9 --keep --small $backup_dir/${db}dump.current";
  system "/bin/cp $backup_dir/${db}dump.current.bz2 $backup_dir/${db}dump.$D.bz2";
}
