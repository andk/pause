#!/usr/bin/perl

=pod

Some of these need a wide screen (ws)

  perl one-off-utils/diff-02packages.pl |awk '{print $1}'|sort|uniq -c|sort -n|perl -nale 'printf "%5d %12s %12s\n", @F'|less

  perl one-off-utils/diff-02packages.pl |awk '{print $3,$4}'|sort|uniq -c|sort -n|perl -nale 'printf "%5d %12s %12s\n", @F'

  perl one-off-utils/diff-02packages.pl |awk '{print $3,$4}'|sort|uniq -c|sort -n|perl -nale 'printf "%5d %12s %12s\n", @F'|less

 (ws) perl one-off-utils/diff-02packages.pl |sort -n -k 3 -k 4 | less

=cut

use strict;
use warnings;

use lib "lib", "privatelib";
use PAUSE;
use Parse::CPAN::Packages;

#-rw-r--r--  1 root root 390344 Sep 15 09:13 /home/ftp/pub/PAUSE/modules/02packages.details.txt-200509150913.gz
#-rw-r--r--  1 root root 390964 Sep 15 04:48 /home/ftp/pub/PAUSE/modules/02packages.details.txt-200509150120.gz

my $p1 = Parse::CPAN::Packages->
    new("/home/ftp/pub/PAUSE/modules/02packages.details.txt-200511.gz") or die;
my $p2 = Parse::CPAN::Packages->
    new("/home/ftp/pub/PAUSE/modules/02packages.details.txt-2005120305.gz") or die;

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
    # no warnings "numeric";
    next if $pkg1->version eq $pkg2->version;
    printf "%-66s %-66s %14s %14s\n",
        $d1->prefix,
            $pkg1->package,
                $pkg1->version,
                    $pkg2->version;
  }
}
