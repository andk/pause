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

OR, if you edit this program, go to line 66 or so and inspect $y which
is the hashref that contains the meta informations. Yes, I edited it,
because there is too much copy and paste in this directory. 2012-09-15
we measure configure_requires on Module::Build.

=cut

use Compress::Zlib;
use File::Find;
use Parse::CPAN::Meta 1.39; # load_file would require 1.42

open my $fh, "/home/ftp/pub/PAUSE/modules/02packages.details.txt.gz" or die;
my $gz = gzopen $fh, "r";
while ($gz->gzreadline($_)) {
  last if /^$/;
}
our($S1,$S2);
while ($gz->gzreadline($_)) {
  my($mod,$ver,$dist) = split " ";
  $dist =~ s/\.(tar\.gz|tgz|zip|tar.bz2|tbz)$//;
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
        return unless $name and exists $S1->{$name};
        my $glob1 = $File::Find::name;
        $glob1 =~ s/\.meta$/.*/;
        my($distro) = grep { ! /\.(?:meta|readme)$/ } glob $glob1;
        my($home, $distropath) = $distro =~ m|^(.*?/authors/id/./../)(.+)|;

        my $glob2 = $distropath;
        $glob2 =~ s/\d+/[0-9]*/g;
        $glob2 = "$home$glob2";
        my(@glob2) = glob $glob2;
        # XXX should check now whether we are the newest of the lot

        my @stat = stat $yaml;
        my $mtime = localtime $stat[9];
        my $y;
        eval { $y = Parse::CPAN::Meta::LoadFile($yaml); };
        my $status;
        if ($@) {
          $status = "yaml_error";
        } else {
          if ($y) {
            unless (ref $y and ref $y eq "HASH"){
              warn "FFn[$File::Find::name]y[$y]";
              return;
            }
            if (exists $y->{configure_requires}) {
              if (ref $y->{configure_requires} eq "HASH") {
                $status = "HASH";
                while (my($k,$v) = each %{$y->{configure_requires}}) {
                  next unless $k eq "Module::Build";
                  printf(
                         "crmb %s %s\n",
                         $v||".",
                         $distropath||$name||"",
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
        printf "stat %s %s\n", $status, $name;
      },
      no_chdir => 1,
     },
     "/home/ftp/pub/PAUSE/authors/id"
);

# Local Variables:
# mode: cperl
# cperl-indent-level: 2
# End:
