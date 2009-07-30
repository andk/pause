#!/usr/bin/perl

=pod

Usage: $0 /home/k/pause/111_sensitive/backup 'authen_pausedump\.(\d\d\d\d)(\d\d)\d+GMT\.bz2'

=cut

use strict;
use warnings;

my($dir,$fpat) = @ARGV;
die "Usage..." unless $fpat;
die "Did not find dir[$dir]" unless -d $dir;
my($qr) = qr($fpat);
my $parens = $fpat =~ tr/(//;
die "Found no opening braces in fpat[$fpat]" unless $parens;
opendir my $dh, $dir or die "Could not opendir '$dir': $!";
my $collect = {};
my $rm = {};
for my $de (readdir $dh) {
  my @catch = $de =~ $qr;
  next unless scalar @catch == $parens;
  local $" = "/";
  $collect->{"@catch"} ||= "";
  if ($collect->{"@catch"}) {
    if ($collect->{"@catch"} gt $de) {
      $rm->{"@catch"}{$collect->{"@catch"}} = undef;
      $collect->{"@catch"} = $de;
    } else {
      $rm->{"@catch"}{$de} = undef;
    }
  } else {
    $collect->{"@catch"} = $de;
  }
}
my @keys = sort keys %$collect;
pop @keys;
for my $k (@keys) {
  print qq{
mkdir -p $dir/$k
mv -iv $dir/$collect->{$k} $dir/$k/$collect->{$k}
};
  for my $de (keys %{$rm->{$k}}) {
    print "rm $dir/$de\n";
  }
}
