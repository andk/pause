#!/usr/bin/perl -w

use strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use PAUSE;
use DBI;
use CPAN::DistnameInfo;

my $db = DBI->connect(
                      $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
                      $PAUSE::Config->{MOD_DATA_SOURCE_USER},
                      $PAUSE::Config->{MOD_DATA_SOURCE_PW},
                      {RaiseError => 0}
                     );

my $ct = 0;
my $dists = $db->selectcol_arrayref("SELECT DISTINCT(dist) FROM packages WHERE distname = '' OR distname IS NULL");
my $total = @$dists;
my $sth = $db->prepare("UPDATE packages SET distname=? WHERE dist=?");
$db->{AutoCommit} = 0;
for my $dist (@$dists) {
    my $name = CPAN::DistnameInfo->new($dist)->dist;
    $sth->execute($name, $dist);
    if (++$ct % 100 == 0) {
        print "done $ct / $total\n";
        $db->commit;
    }
}
$db->commit;
$sth->finish;