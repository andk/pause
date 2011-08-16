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

=item B<--help|h!>

This help

=item B<--pass=s>

Password for user root

=back

=head1 DESCRIPTION

Neil Bowers asked me for statistics about distros:

What's the staleness of distributions? This will be interesting both
in the cumulative and distribution view.

    distname,month-of-first-upload,month-of-most-recent-upload

There may be other sources that give a different answer but the first
thing that came to my mind was to take the uris table. It has the
advantage to contain everything that pause still knows.

As far as I remember I had some data loss in the early days but I
think that was sometime 1996.

There are also data included that were only test data and some of
those have been removed but I expect there is no big distortion from
that.

Finally this script follows CPAN::Distnameinfo which eliminates some
4700 files and all of those seem to be dispensable.

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
use Hash::Util qw(lock_keys);

our %Opt;
lock_keys %Opt, map { /([^=]+)/ } @opt;
GetOptions(\%Opt,
           @opt,
          ) or pod2usage(1);

use CPAN::DistnameInfo;
use DBI;
use File::Basename qw(basename);
use YAML::XS;

my $dbh = DBI->connect("dbi:mysql:mod","root",$Opt{pass});
my $st = "SELECT uriid, dverified from uris where dverified is not null and dverified <> ''";
my $sth = $dbh->prepare($st);
$sth->execute;
my $i = 0;
my $cnt_could_not = 0;
my $S;
ROW: while (my($id,$dverified) = $sth->fetchrow_array) {
    $i++;
    my $d = CPAN::DistnameInfo->new("authors/id/$id");
    my $dist = $d->dist;
    unless ($dist) {
        # warn "Could not determine dist in id[$id]\n";
        $cnt_could_not++;
        next ROW;
    }
    next ROW unless $dist =~ /^[A-Za-z]/;
    my $cpanid = $d->cpanid;
    my $first = $S->{$dist}{first} //= 2147483648;
    my $last  = $S->{$dist}{last}  //= 0;
    $S->{$dist}{cpanid}{$cpanid} = undef;
    $S->{$dist}{cnt}++;
    if ($dverified < $first) {
        $S->{$dist}{first} = $dverified;
    }
    if ($dverified > $last) {
        $S->{$dist}{last} = $dverified;
    }
}
# warn "Summary: could not determine dist in $cnt_could_not cases\n";
for my $dist (keys %$S) {
    my @a = sort keys %{delete $S->{$dist}{cpanid};};
    $S->{$dist}{cpanids} = \@a;
}
print YAML::XS::Dump $S;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
