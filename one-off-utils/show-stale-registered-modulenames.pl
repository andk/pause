#!/usr/bin/perl

=pod

posted by Steffen mueller on modules@perl.org on Aug 31, 2007

=cut

use strict;
use warnings;
{
  open my $fh1, '<', "03modlist.data" or die;
  while (<$fh1>) {
    next unless /^\s*$/;
    last;
  }
  local $/;
  my $code = <$fh1>;
  warn sprintf "length(code)[%d]", length $code;
  eval $code;
  close $fh1;
}

open my $fh, '<', "02packages.details.txt" or die $!;
my %packages;
my $started = 0;
while (<$fh>) {
  $started = 1, next if /^\s*$/;
  next if not $started;
  chomp;
  my @rec = split /\s+/, $_;
  $rec[2] =~ /^[\w-]\/[\w-]{2}\/([\w-]+)\// or die("Invalid dist name:
$rec[2]!");
  my $author = $1;
  $packages{$rec[0]} = {
    name => $rec[0],
    dist => $rec[2],
    author => $author,
  };
}
close $fh;

my $modhash = CPAN::Modulelist::data();

foreach my $module (keys %$modhash) {
  warn "Checking $module\n";
  my $pkg = $packages{$module};
  if (not defined $pkg) {
    print "$module\n";
    next;
  }
}

