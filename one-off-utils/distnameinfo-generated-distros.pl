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

=back

=head1 DESCRIPTION



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

my $dbh = DBI->connect("dbi:mysql:mod","root","fi8zu3xu");
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
