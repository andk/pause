#!/usr/bin/perl -w

use strict;

my $DIR = "/home/ftp/pub/PAUSE/PAUSE-data";
my @m=gmtime;
$m[5]+=1900;
$m[4]++;
my $D = sprintf "%04d%02d%02d%02d%02dGMT",@m[5,4,3,2,1];

use lib "/home/k/PAUSE/lib";
use PAUSE ();
# unless ($Dbh = DBI->connect(
#                             $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
#                             $PAUSE::Config->{MOD_DATA_SOURCE_USER},
#                             $PAUSE::Config->{MOD_DATA_SOURCE_PW},
#                             { RaiseError => 1 }
#                            )) {
#   die "Connect to database not possible: $DBI::errstr\n";
# }

my($dbi,$dbengine,$db) = split /:/, $PAUSE::Config->{MOD_DATA_SOURCE_NAME};
die "Script would not work for $dbengine" unless $dbengine =~ /mysql/i;

system "/usr/local/bin/mysqldump --lock-tables --add-drop-table -u '$PAUSE::Config->{MOD_DATA_SOURCE_USER}' -P '$PAUSE::Config->{MOD_DATA_SOURCE_PW}' '$db' > $DIR/.moddump.current";

my $BZIP = "/usr/local/bin/bzip2";
$BZIP = "/usr/bin/bzip2" unless -x $BZIP;
die "where is BZIP" unless -x $BZIP;

rename "$DIR/.moddump.current", "$DIR/moddump.current";
unlink "$DIR/moddump.current.bz2";
system "$BZIP -9 --keep --small $DIR/moddump.current";
system "/bin/cp $DIR/moddump.current.bz2 $DIR/moddump.$D.bz2";
