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

Batch processing of modules either in the mods table or in the perms table into primeur.

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
my $sth6 = $dbh->prepare("select userid from perms where package=?");
MOD: for my $modid (@mods) {
    my $wantmove = 0;
    my($mv_userid, $mlstatus, $userid);
    $sth2->execute($modid);
    if ($sth2->rows >= 1) {
        ($mlstatus, $userid) = $sth2->fetchrow_array;
    } else {
        warn "Warning: $modid not in mods, trying perms instead\n";
        $sth6->execute($modid);
        if ($sth6->rows >= 1) {
            ($userid) = $sth6->fetchrow_array;
            $mlstatus = 'from-perms';
        } else {
            warn "Warning: Found no record for $modid, skipping\n";
        }
    }
    if ($mlstatus) {
        if ($mlstatus =~ /^(list|delete|from-perms|hide)$/) {
            $mv_userid = $userid;
            $wantmove=1;
        } else {
            warn "Warning: Will not move to primeur: $modid (mlstatus=$mlstatus)\n";
        }
    }
    if ($wantmove) {
        $sth4->execute($modid);
        my $rows = $sth4->fetchall_arrayref;
        my $can_remove = 0;
        if (@$rows) {
            if ($rows->[0][0] eq $mv_userid) {
                warn "modid=$modid,user=$mv_userid already in primeur";
                $can_remove = 1;
            } else {
                warn "primeur occupied by modid=$modid,user=$rows->[0][0]; cannot move";
            }
        } else {
            if ($Opt{"dry-run"}) {
                warn "Would now try to insert modid=$modid,user=$mv_userid into primeur; this will cause can_remove to be set and cause a delete of $modid in mods\n";
            } else {
                warn "Inserting modid=$modid,user=$mv_userid into primeur\n";
                $sth5->execute($modid,$mv_userid);
            }
            $can_remove = 1;
        }
        if ($can_remove) {
            if ($mlstatus eq "delete") {
                warn "mlstatus already 'delete' for $modid in mods table\n";
            } elsif ($mlstatus eq "from-perms") {
                warn "mlstatus was not in mods, for $modid nothing left to do in mods table\n";
            } elsif ($Opt{"dry-run"}) {
                warn "Would now set mlstatus for $modid in mods to delete";
            } else {
                warn "Setting mlstatus for $modid in mods to delete";
                $sth3->execute($modid);
            }
        }
    } else {
        warn "Warning: no reason found to change anything for modid '$modid'; maybe try: insert into primeur (package,userid) values ('$modid','...')\n";
    }
}


# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
