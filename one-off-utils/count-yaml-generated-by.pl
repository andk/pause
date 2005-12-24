#!/usr/bin/perl

=pod

Slaven suggests to ignore MET.yml provede by EUMM before 6.25_01

The output of this script must be postprocessed like so:

sed -e 's| ./../.*||' count-yaml-generated-by.pl.out|sort|uniq -c

And from that we learn that 4115 distros have their META.yml produced
by EUMM 6.17

=cut

use strict;
use version;
use warnings;

use Compress::Zlib;
use File::Find;
use YAML;

our($myml);
find(
     {
      wanted => sub {
        return unless /\.meta$/;
        my $yaml = $_;
        my($name) =
            $File::Find::name =~ m|([A-Z]/[A-Z][A-Z]/[A-Z][A-Z-]*[A-Z]/.+)\.meta$|;
        my $y;
        eval { $y = YAML::LoadFile($yaml); };
        my $status;
        if ($@) {
          $status = "yaml_error";
        } else {
          if ($y) {
            die unless ref $y and ref $y eq "HASH";
            if (exists $y->{generated_by}) {
              $status = $y->{generated_by};
            } else {
              $status = "no_generated_by";
            }
          } else {
            $status = "no_yaml";
          }
        }
        die unless $status;
        printf "%s %s\n", $status, $name;
      },
     },
     "/home/ftp/pub/PAUSE/authors/id"
);

