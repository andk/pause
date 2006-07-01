#!/usr/bin/perl

use strict;
use warnings;

my %jobs;
while (<>) {
  chomp;
  my($date,$time,$proc,$what) = split " ", $_, 4;
  if ($what =~ /reached/) { # later ^EOJ
    printf "%5d: %s\n_______%s %s %s\n", $proc, $jobs{$proc}, $date, $time, $what;
    delete $jobs{$proc};
  } elsif ($jobs{$proc}) {
    $jobs{$proc} .= "\n       $date $time $what";
  } else {
    $jobs{$proc} = "$date $time $what";
  }
}
