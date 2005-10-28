#!/usr/bin/perl

=pod

Ron Savage had an upload with a META.yml that wrongly contained an
empty provides hashref. This program tries to get evidence how often
this happens and under which circumstances.

The strategy is to tag each yaml file with a status and output that on
stdout. My strategy is to run the cycle:

  perl count-yaml-provides-empty.pl > count-yaml-provides-empty.out
  awk '{print $1}' count-yaml-provides-empty.out | sort | uniq -c

and then investigate individual cases and refine on the status string.

I found 49 distros hit by this bug. I then checked manually each of
them and found, all except those by Ron and two more by SSCOTTO
(Salvatore E. ScottoDiLuzio) came after 2005-04-19, the day when PAUSE
started supporting the provides hash.

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
            if (exists $y->{provides}) {
              if (ref $y->{provides} and ref  $y->{provides} eq "HASH") {
                if (my $k = keys %{$y->{provides}}) {
                  $status = "has_keys";
                } else {
                  $status = "empty";
                }
                if (exists $y->{generated_by}) {
                  if (my($v) = $y->{generated_by} =~ /Module::Build version ([\d\.]+)/) {
                    $status .= "_mb";
                    $v = version->new($v)->numify;
                    if ($v < 0.26) {
                      $status .= "_lt0.26";
                    } else {
                      $status .= "_ge0.26";
                    }
                  } else {
                    $status .= "_other";
                  }
                } else {
                  $status .= "_no_generated_by";
                }
              } else {
                $status = "provides_not_hash";
              }
            } else {
              $status = "no_provides";
            }
          } else {
            $status = "yaml_no_scalar";
          }
        }
        die unless $status;
        printf "%s %s\n", $status, $name;
      },
     },
     "/home/ftp/pub/PAUSE/authors/id"
);

