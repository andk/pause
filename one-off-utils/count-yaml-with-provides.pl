#!/usr/bin/perl

use strict;
use warnings;

use File::Find;
use YAML;

find(
     {
      wanted => sub {
        return unless /\.meta$/;
        my $yaml = $_;
        my $c;
        eval { $c = YAML::LoadFile($yaml); };
        if ($@) {
          if ($@ =~ /msg: Unrecognized implicit value/) {
            # let's retry, but let's not expect that this will work.
            # MakeMaker 6.16 had a bug that could be fixed like this,
            # at least for Pod::Simple

            my $cat = do { open my($fh), $yaml or die; local $/; <$fh> };
            $cat =~ s/:(\s+)(\S+)$/:$1"$2"/mg;
            eval { $c = YAML::Load $cat; };
            if ($@) {
              $c = {ERROR => "META.yml found but error encountered while loading: $@"};
            }
          } else {
            $c = {ERROR => "META.yml found but error encountered while loading: $@"};
          }
        }
        my($gen) = $c->{generated_by} || "";
        $gen =~ s/\s.*// if $gen;
        print exists $c->{provides} ? "$gen\n" : "has not\n";
      },
     },
     "/home/ftp/pub/PAUSE/authors/id"
);
