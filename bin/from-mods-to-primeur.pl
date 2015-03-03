#!/usr/bin/perl

# use 5.010;
use strict;
use warnings;

=head1 NAME



=head1 SYNOPSIS

 from-mods-to-primeur [OPTIONS] distro ...

=head1 OPTIONS

=over 8

=cut

my @opt = <<'=back' =~ /B<--(\S+)>/g;

=item B<--byuser=s@>

If given, take all modules by this user from mods table and treat them
as if they were found on the command line.

=item B<--dry-run|n!>

Only reports what it would do.

=item B<--help|h!>

This help

=back

=head1 DESCRIPTION

Batch processing of modules in the mods table into primeur.

=cut


use FindBin;
use lib "$FindBin::Bin/../lib";
BEGIN {
    push @INC, qw(       );
}

use Dumpvalue;
use File::Basename qw(dirname);
use File::Path qw(mkpath);
use File::Spec;
use File::Temp;
use Getopt::Long;
use Pod::Usage;
use Hash::Util qw(lock_keys);

our %Opt;
lock_keys %Opt, map { /([^=|!]+)/ } @opt;
GetOptions(\%Opt,
           @opt,
          ) or pod2usage(1);
if ($Opt{help}) {
    pod2usage(0);
}
use List::MoreUtils qw(uniq);
use PAUSE;
use DBI;
my $dbh = DBI->connect(
    $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
    $PAUSE::Config->{MOD_DATA_SOURCE_USER},
    $PAUSE::Config->{MOD_DATA_SOURCE_PW},
    {RaiseError => 0}
);
my(@mods) = @ARGV;
my $sth1 = $dbh->prepare("select modid from mods where userid=?");
for my $userid (@{$Opt{byuser}}) {
    $sth1->execute($userid);
    while (my($modid) = $sth1->fetchrow_array) {
        push @mods, $modid;
    }
}
unless (@mods){
    warn "Arguments expected, got none";
    pod2usage(1);
}
@mods = uniq @mods;
my $sth2 = $dbh->prepare("select mlstatus,userid from mods where modid=?");
my $sth3 = $dbh->prepare("update mods set mlstatus='delete' where modid=?");
my $sth4 = $dbh->prepare("select userid from primeur where package=?");
my $sth5 = $dbh->prepare("insert into primeur (package,userid) values (?,?)");
MOD: for my $modid (@mods) {
    $sth2->execute($modid);
    unless ($sth2->rows >= 1) {
        warn "Found no record for $modid, skipping";
    }
    my $wantmove = 0;
    my $mv_userid;
    while (my($mlstatus,$userid) = $sth2->fetchrow_array) {
        if ($mlstatus eq "list") {
            $mv_userid = $userid;
            $wantmove=1;
        } elsif ($mlstatus eq "delete") {
            # delete turned out to be the same case as list when bdfoy
            # tried to give an adoptme module away (Math::FFT)
            $mv_userid = $userid;
            $wantmove=1;
        } else {
            warn "Will not move to primeur: $modid (mlstatus=$mlstatus)\n";
        }
    }
    if ($wantmove) {
        $sth4->execute($modid);
        my $rows = $sth4->fetchall_arrayref;
        my $can_remove = 0;
        if (@$rows) {
            if ($rows->[0][0] eq $mv_userid) {
                warn "$modid/$mv_userid already in primeur";
                $can_remove = 1;
            } else {
                warn "primeur occupied by $modid/$rows->[0][0], cannot move";
            }
        } else {
            if ($Opt{"dry-run"}) {
                warn "Would now try to insert $modid/$mv_userid into primeur; this may cause can_remove to be set and cause a delete of $modid in mods";
            } else {
                $sth5->execute($modid,$mv_userid);
                $can_remove = 1;
            }
        }
        if ($can_remove) {
            if ($Opt{"dry-run"}) {
                warn "Would now set mlstatus for $modid in mods to delete";
            } else {
                $sth3->execute($modid);
            }
        }
    }
}


# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
