#!/usr/bin/perl

use strict;
use version;
use warnings;

=pod

CPAN.pm must deal with requires => { foo => ">= 12, > 11, != 5" } and
so I want to see what I should test against.

As usual, run

sed -e 's| ./../.*||' count-yaml-requires.pl.out|sort|uniq -c

to get an overview of what kinds of status we encounter or

perl -nale 'print $1 if /\]v\[(.*?)\]/' count-yaml-requires.pl.out|sort|uniq -c

to see the version requirements in the wild.



=cut

use Compress::Zlib;
use File::Find;
use YAML;

open my $fh, "/home/ftp/pub/PAUSE/modules/02packages.details.txt.gz" or die;
my $gz = gzopen $fh, "r";
while ($gz->gzreadline($_)) {
  last if /^$/;
}
our($S1,$S2);
while ($gz->gzreadline($_)) {
  my($mod,$ver,$dist) = split " ";
  $dist =~ s/\.(tar\.gz|tgz|zip)$//;
  $S1->{$dist}{$mod} = $ver;
}
$gz->gzclose;
close $fh;
warn sprintf "S1 has %d keys", scalar keys %$S1;
our($myml);
find(
     {
      wanted => sub {
        return unless /\.meta$/;
        my $yaml = $_;
        my($name) =
            $File::Find::name =~ m|([A-Z]/[A-Z][A-Z]/[A-Z][A-Z-]*[A-Z]/.+)\.meta$|;
        return unless exists $S1->{$name};
        my @stat = stat $yaml;
        my $mtime = localtime $stat[9];
        my $y;
        eval { $y = YAML::LoadFile($yaml); };
        my $status;
        if ($@) {
          $status = "yaml_error";
        } else {
          if ($y) {
            die unless ref $y and ref $y eq "HASH";
            if (exists $y->{requires}) {
              if (ref $y->{requires} eq "HASH") {
                $status = "HASH";
                while (my($k,$v) = each %{$y->{requires}}) {
                  printf(
                         "k[%s]v[%s]g[%s]m[%s] %s\n",
                         $k,
                         $v,
                         $y->{generated_by}||"",
                         $mtime,
                         $name,
                        );
                }
              } else {
                $status = "no_hash";
              }
            } else {
              $status = "no_requires";
            }
          } else {
            $status = "no_yaml";
          }
        }
        die unless $status;
        # printf "%s %s\n", $status, $name;
      },
     },
     "/home/ftp/pub/PAUSE/authors/id"
);

