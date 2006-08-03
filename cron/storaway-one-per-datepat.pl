#!/usr/bin/perl

=pod

Usage: $0 /home/k/PAUSE/111_sensitive/backup 'authen_pausedump\.(\d\d\d\d)(\d\d)\d+GMT\.bz2'

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
$collect = {};
$rm = {};
for my $de (readdir $dir) {
  my @catch = $de =~ $qr;
  next unless scalar @catch == $paren;
  local $" = "/";
  $collect->{"@catch"} ||= "";
  if ($collect->{"@catch"}) {
    if ($collect->{"@catch"} lt $de) {
      $rm->{"@catch"}{$collect->{"@catch"}} = undef;
      $collect->{"@catch"}{$de} = undef;
    } else {
      $rm->{"@catch"}{$de} = undef;
    }
  } else {
    $collect->{"@catch"} = $de;
  }
}
for my $k (keys %$collect) {
  print qq{
mkdir -p $dir/$k
mv $dir/$collect->{$k} $dir/$k/$collect->{$k}
};
  for my $de (keys %{$rm->{$k}}) {
    print "rm $dir/$de\n";
  }
}
