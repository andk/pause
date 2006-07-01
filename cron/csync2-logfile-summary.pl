#!/usr/bin/perl

use strict;
use warnings;
use Text::Wrap;
$Text::Wrap::huge = "overflow";
$Text::Wrap::columns = $ENV{COLUMNS}||80;

my %jobs;
while (<>) {
  chomp;
  my($date,$time,$proc,$what) = split " ", $_, 4;
  if ($what =~ /reached/) { # later ^EOJ
    print wrap("","    ",sprintf "%5d: %s|%s %s %s\n", $proc, $jobs{$proc}, $date, $time, $what);
    delete $jobs{$proc};
  } elsif ($jobs{$proc}) {
    $jobs{$proc} .= "|$date $time $what";
  } else {
    $jobs{$proc} = "$date $time $what";
  }
}
