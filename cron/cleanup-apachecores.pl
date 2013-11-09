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

=item B<--coredir=s>

Directory to cleanup. Defaults to /opt/apache/cores.

=item B<--filerx=s>

Regular expression that filters files subject to the cleanup. Defaults to C</^core\.\d+\z>

=item B<--help|h!>

This help

=item B<--keep=i>

Number of files to keep. Defaults to 10.

=item B<--verbose!>

Report about deletions.

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
use Pod::Usage;
use Hash::Util qw(lock_keys);

our %Opt;
lock_keys %Opt, map { /([^=|!]+)/ } @opt;
GetOptions(\%Opt,
           @opt,
          ) or pod2usage(1);

$Opt{coredir} ||= "/opt/apache/cores";
$Opt{keep} ||= 10;
$Opt{filerx} ||= q{^core\.\d+\z};
my $filerxqr = qr{$Opt{filerx}};
opendir my $dh, $Opt{coredir} or die "Could not open '$Opt{coredir}': $!";
my @ls;
for my $dirent (readdir $dh) {
    next unless $dirent =~ $filerxqr;
    push @ls, "$Opt{coredir}/$dirent";
}
my @ls_sorted_newest_first = map { $_->[0] }
    sort { $a->[1] <=> $b->[1] }
    map { [$_, -M $_] }
    @ls;
while (@ls_sorted_newest_first > $Opt{keep}) {
    my $unlink = pop @ls_sorted_newest_first;
    print STDERR "About to delete '$unlink'..." if $Opt{verbose};
    unlink $unlink or die "Could not unlink '$unlink': $!";
    print STDERR "Done\n" if $Opt{verbose};
}

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
