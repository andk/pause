#!/usr/bin/perl

# use 5.010;
use strict;
use warnings;

=head1 NAME



=head1 SYNOPSIS



=head1 OPTIONS

=over 8

=cut

my @opt = <<'=back' =~ /B<--(\S+)>/g;

=item B<--dry-run|n!>

Run the from-mods-to-primeur.pl with the --dry-run option.

=item B<--help|h!>

This help

=back

=head1 DESCRIPTION

As in the previous batchfiles, converting-m-to-f-*.pl, Neil
Bowers sent me the data and I wrapped them into the script.

The difference this time is, the format has one field more:

	delete  remove this entry
	c       downgrade it to a ‘c’ (there are examples of both ‘m’ and
	        ‘f’ being downgraded)
	f       downgrade an ‘m’ to an ‘f’
	add     add this permission

When we reached circa line 335 of the list after the DATA filehandle,
we discovered the need to have the upgrade c=>f option too and
implemented it:

        f       downgrade m=>f or upgrade c=>f

head2 EXAMPLES

 AI::nnflex,CCOLBOURN,f,delete
 AI::NNFlex,CCOLBOURN,m,f
 Tk::Pod,TKML,m,c
 Tk::Statusbar,ZABEL,m,delete
 Time::Format,ROODE,c,f
 JSON::Assert,SGREEN,f,add
 Net::MAC::Vendor,ETHER,f,add
 Sane,PABLROD,f,delete
 Algorithm::LCS,ADOPTME,f,add

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
$Opt{"dry-run"} //= 0;
my @dry_run;
push @dry_run, "--dry-run" if $Opt{"dry-run"};
use Time::HiRes qw(sleep);
use PAUSE;
use DBI;
my $dbh = DBI->connect(
    $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
    $PAUSE::Config->{MOD_DATA_SOURCE_USER},
    $PAUSE::Config->{MOD_DATA_SOURCE_PW},
    {RaiseError => 0}
);

my $sth1 = $dbh->prepare("update mods set mlstatus='delete' where modid=? and userid=?");
my $sth2 = $dbh->prepare("delete from primeur where package=? and userid=?");
my $sth3 = $dbh->prepare("delete from perms where package=? and userid=?");
my $sth4 = $dbh->prepare("insert into perms (package,userid) values (?,?)");
my $sth5 = $dbh->prepare("insert into primeur (package,userid) values (?,?)");

my $i = 0;
while (<DATA>) {
    chomp;
    my $csv = $_;
    next if /^\s*$/;
    next if /^#/;
    my($m,$a,$type,$action) = split /,/, $csv;
    for ($m,$a,$type,$action) {
        s/\s//g;
    }
    die "illegal type" unless $type =~ /[mfc]/;
    my $t = scalar localtime;
    $i++;
    warn sprintf "(%d) %s: %s %s type=%s action=%s\n", $i, $t, $m, $a, $type, $action;
    if ($action eq "delete") {
        if ($type eq "m") {
            if ($Opt{"dry-run"}){
                warn "Would update mods 1\n";
            } else {
                warn "Setting mlstatus for modid=$m,userid=$a in mods to 'delete'";
                $sth1->execute($m,$a);
            }
        } elsif ($type eq "f") {
            if ($Opt{"dry-run"}){
                warn "Would delete first-come 1\n";
            } else {
                warn "Deleting from primeur package=$m,userid=$a";
                $sth2->execute($m,$a);
            }
        } elsif ($type eq "c") {
            if ($Opt{"dry-run"}){
                warn "Would delete comaint\n";
            } else {
                warn "Deleting from perms package=$m,userid=$a";
                $sth3->execute($m,$a);
            }
        } else {
            die "illegal";
        }
    } elsif ($action eq "c") {
        if ($type eq "m") {
            if ($Opt{"dry-run"}){
                warn "Would update mods 2 AND Would insert comaint 1\n";
            } else {
                warn "Setting mlstatus for modid=$m,userid=$a in mods to 'delete'";
                $sth1->execute($m,$a);
                warn "Inserting into perms modid=$m,userid=$a (may fail with 'Duplicate entry')";
                $sth4->execute($m,$a);
            }
        } elsif ($type eq "f") {
            if ($Opt{"dry-run"}){
                warn "Would delete first-come 2 AND Would insert comaint 2\n";
            } else {
                warn "Deleting from primeur package=$m,userid=$a";
                $sth2->execute($m,$a);
                warn "Inserting into perms modid=$m,userid=$a (may fail with 'Duplicate entry')";
                $sth4->execute($m,$a);
            }
        } else {
            die "illegal";
        }
    } elsif ($action eq "f") {
        if ($type eq "m") {
            if ($Opt{"dry-run"}){
                warn "Would call mods-to-primeur\n";
            } else {
                0 == system "/opt/perl/current/bin/perl", "-Iprivatelib", "-Ilib", "bin/from-mods-to-primeur.pl", @dry_run, $m or die "Alert: $t: Problem while running from-mods-to-primeur for '$m'";
            }
        } elsif ($type eq "c") {
            if ($Opt{"dry-run"}){
                warn "Would delete comaint AND Would insert first-come\n";
            } else {
                warn "Deleting from perms package=$m,userid=$a";
                $sth3->execute($m,$a);
                warn "Inserting into primeur modid=$m,userid=$a";
                $sth5->execute($m,$a);
            }
        } else {
            die "illegal";
        }
    } elsif ($action eq "add") {
        if ($type eq "f") {
            if ($Opt{"dry-run"}){
                warn "Would insert first-come\n";
            } else {
                warn "Inserting into primeur modid=$m,userid=$a";
                $sth5->execute($m,$a);
            }
        } elsif ($type eq "c") {
            if ($Opt{"dry-run"}){
                warn "Would insert comaint 3\n";
            } else {
                warn "Inserting into perms modid=$m,userid=$a (may fail with 'Duplicate entry')";
                $sth4->execute($m,$a);
            }
        } else {
            die "illegal";
        }
    }
    sleep 0.08;
}

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:

#XML::LibXML::Iterator,PAJAS,f,add
#MHonArc,EHOOD,f,add
#Module::CoreList,P5P,f,add
__END__
libapreq2,ISAAC,f,add
