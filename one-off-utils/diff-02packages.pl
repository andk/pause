#!/usr/bin/perl

=pod


=cut

use strict;
use warnings;

use lib "lib", "privatelib";
use PAUSE;
use Parse::CPAN::Packages;

my $p1 = Parse::CPAN::Packages->
    new("/home/ftp/pub/PAUSE/modules/02packages.details.txt-20050804.gz") or die;
my $p2 = Parse::CPAN::Packages->
    new("/home/ftp/pub/PAUSE/modules/02packages.details.txt-20050808.gz") or die;

for my $d1 ($p1->latest_distributions){
  # printf "%s\n", $d1->dist;
  for my $pkg1 (@{$d1->packages}) {
    my $pkg2 = $p2->package($pkg1->package);
    if (!defined $pkg2) {
      printf "%s %s %s [MISSING]\n",
          $d1->prefix,
              $pkg1->package,
                  $pkg1->version;
      next;
    }
    if ($pkg2->distribution->prefix ne $d1->prefix) {
      # due to inconsistencies in the permissions tables of PAUSE and testbox
      next;
    }
    next if $pkg1->version eq $pkg2->version;
    no warnings "numeric";
    next if $pkg1->version == $pkg2->version;
    printf "%s %s %s %s\n",
        $d1->prefix,
            $pkg1->package,
                $pkg1->version,
                    $pkg2->version;
  }
}
