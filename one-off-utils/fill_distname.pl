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
my $rows = $db->selectall_arrayref("SELECT dist, package FROM packages WHERE distname = '' OR distname IS NULL");
my $total = @$rows;
my $sth = $db->prepare("UPDATE packages SET distname=? WHERE package=?");
$db->{AutoCommit} = 0;
for my $row (@$rows) {
    my ($dist, $package) = @$row;
    my $name = CPAN::DistnameInfo->new($dist)->dist;
    $sth->execute($name, $package);
    if (++$ct % 1000 == 0) {
        print "done $ct / $total\n";
        $db->commit;
    }
}
$db->commit;
$sth->finish;