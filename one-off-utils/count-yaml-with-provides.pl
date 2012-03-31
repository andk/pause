#!/usr/bin/perl

use strict;
use warnings;

=pod

This program was used to investigate differences between decisions
taken by the indexer and the provides hashref in the accompanying
META.yml files. The investigation took place before the indexer itself
looked into the provides hashref. At the bottom of the program is a
pod section that talks about findings and consequences

As I do not remember how this program was called and how the output
looked like, I reran it 2005-12-22 and the output went to STDERR, was
chaotic and contained lots of Data::Dumper and in between:

S1 has 10549 keys at count-yaml-with-provides.pl line 37.
S2 has 2477 keys at count-yaml-with-provides.pl line 92.
schnitt[981]S1[9568]s2[1496] at count-yaml-with-provides.pl line 111.
schnitt[981]schnittOK[763] at count-yaml-with-provides.pl line 153.

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
        return unless $c;
        return unless ref $c eq "HASH";
        my($name) =
            $File::Find::name =~ m|([A-Z]/[A-Z][A-Z]/[A-Z][A-Z-]*[A-Z]/.+)\.meta$|;
        if (exists $c->{provides}) {
          my $accept;
          if (exists $c->{generated_by}) {
            if (my($v) = $c->{generated_by} =~ /Module::Build version ([\d\.]+)/) {
              if ($v eq "0.250.0") {
                $accept++;
              } elsif ($v >= 0.19) {
                $accept++;
              }
            }
          } else {
            $accept++;
          }
          if ($accept) {
            for my $k (keys %{$c->{provides}||{}}) {
              $S2->{$name}{$k} =
                  exists $c->{provides}{$k}{version} ?
                      $c->{provides}{$k}{version} :
                          "undef";
            }
          }
        }
      },
     },
     "/home/ftp/pub/PAUSE/authors/id"
);

warn sprintf "S2 has %d keys", scalar keys %$S2;
my %A = map { $_ => undef } keys %$S1, keys %$S2;
my $schnitt = 0;
my $s1only = 0;
my $s2only = 0;
for my $k (keys %A) {
  if (exists $S1->{$k}) {
    if (exists $S2->{$k}) {
      $schnitt++;
      $A{$k} = 12;
    } else {
      $s1only++;
      $A{$k} = 1;
    }
  } else {
    $s2only++; # mostly older versions that are not anymore in 02modules
    $A{$k} = 2;
  }
}
warn "schnitt[$schnitt]S1[$s1only]s2[$s2only]";

# x map { $S1->{$_}, $S2->{$_} } grep { $A{$_} eq 12 } keys %A
use Data::Compare qw(Compare);
my $schnittOK = 0;
my @all = sort grep { $A{$_} eq 12 } keys %A;
for my $i (0..$#all) {
  my $k = $all[$i];
  my($base) = $k =~ m/(.+-)[\d\.]+/;
  if ($base) {
    # skip old versions of the same distribution
    next if $all[$i+1] and substr($all[$i+1],0,length($base)) eq $base;
  }
  my $s1 = $S1->{$k};
  my $s2 = $S2->{$k};
  for my $k1 (keys %$s1) {
    next if $s1->{$k1} eq "undef";
    1 while $s1->{$k1} =~ s/(\d)_(\d)/$1$2/;
    $s1->{$k1}+=0;
  }
  for my $k2 (keys %$s2) {
    next if $s2->{$k2} eq "undef";
    1 while $s2->{$k2} =~ s/(\d)_(\d)/$1$2/;
    $s2->{$k2}+=0;
  }
  if (Compare $S1->{$k}, $S2->{$k}){ # equal
    $schnittOK++;
  } else {
    warn sprintf "k[%s]s1 mods[%d]s2 mods [%d]", $k,
        scalar keys %$s1,
        scalar keys %$s2;
    require Data::Dumper; print STDERR "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . Data::Dumper->new([$s1,$s2],[qw()])->Indent(1)->Useqq(1)->Dump; # XXX
    for my $k (keys %$s1) {
      if (exists $s2->{$k} and $s1->{$k} eq $s2->{$k}) {
        delete $s1->{$k};
        delete $s2->{$k};
      }
    }
    require Data::Dumper; print STDERR "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . Data::Dumper->new([$s1,$s2],[qw()])->Indent(1)->Useqq(1)->Dump; # XXX

    warn "inner HERE";
  }
}
warn "schnitt[$schnitt]schnittOK[$schnittOK]";
# jetzt $S1 gegen $S2 checken...
warn "outer HERE about to leave";

=pod

Differences between the indexer and the "provides" fields by Module::Build:


1. M:B lists namespaces with a $VERSION of       | Reasonable
   undef without a version at all                |
                                                 |
2. M:B cuts off trailing zeroes                  | Harmless
                                                 |
3. M:B leaves underscores in numbers             | I will remove; no, I will treat as dev
                                                 |
4. Bug in M:B, it lists                          | I will clean up trailing "::"
                                                 |
  'Acme::MetaSyntactic::':                       |
    file: lib/Acme/MetaSyntactic.pm              |
    version: 0.16                                |
                                                 |
   see the trailing "::"                         |
                                                 |
5. Bug in M:B, it lists                          | Discuss on mailing list?
                                                 |
  HTTP::Proxy::FilterStack:                      |
    file: lib/HTTP/Proxy.pm                      |
    version: 0.15                                |
                                                 |
   The namespace is correct, but it has no       |
   $VERSION assigned. Unsure if this is a        |
   good solution or a bad one.                   |
                                                 |
6. Has M:B issues with YAML 0.38? No, but        | Bugreport sent
   apparently one must re-install M:B in         |
   order to get YAML support                     |
                                                 |
7. this script (count-yaml-....pl) is            | Nothing to do
   confused with                                 |
   BULB/Config-Maker-0.001.tar.gz vs             |
   BULB/Config-Maker-0.006.tar.gz: The           |
   former use M:B, the latter not, so            |
   although everything was ok in 0.006,          |
   this script complained about 0.001.           |
                                                 |
8. CDAWSON/Smil-0.898.tar.gz distributes         | Bugreport sent
   an old META.yml.                              |
                                                 |
9. M:B seems to support unlimited depth          | OK
   whereas the indexer stops at 4 levels         |
   (I think)                                     |
                                                 |
10. M:B doesn't see the eg/ Directory of         | OK
    CWINTERS/Workflow-0.15.tar.gz, I             |
    cannot recognize why, but it seems OK.       |
                                                 |
11. M:B lists                                    | 11-14 are all the same problem:
                                                 | Do we want to have Module names
  text:                                          | mentioned that are not matching
    file: lib/Module/CPANTS/Generator/Unpack.pm  | the filename?
    version: 0.26                                |
                                                 | pro: good against namespace
    because somewhere down in the code           |      clashes
    appears a text snippet "package text"        |
    on one line.                                 | con: these namespaces cannot be
                                                 |      accessed with "require"
12. M:B discoveres that                          |
                                                 | con: authors can easily add name
  super:                                         |      spaces automatically, but
    file: lib/Class/ClassDecorator.pm            |      they cannot as easily remove
    version: 0.02                                |      them
                                                 |
  Here it is correctly finding a package         |
  name that is provided near the end of          |
  the file and may lead to a namespace           |
  clash                                          |
                                                 |
13. M:B lists main!                              |
                                                 |
  main:                                          |
    file: lib/Apache/SSI.pm                      |
    version: 2.19                                |
                                                 |
14. M:B lists                                    |
                                                 |
  filename:                                      |
    file: lib/Devel/ebug.pm                      |
    version: 0.37                                |
                                                 |
   just because of this line in a string:        |
                                                 |
   package filename line codeline ...            |
                                                 |
                                                 |
15. Sometimes the difference between the         |
    indexer and M:B is due to                    |
    permissions in the database.                 |
                                                 |
16. In P/PT/PTANDLER/PBib/Bundle-PBib-2.08       | I will only accept *.pm
    Module::Build lists a long list of           |
    nonsense that the indexer doesn't have       |
    because he has the principle of              |
    "simile". bp_output cannot become a          |
    package with the indexer when it is in       |
    a file                                       |
    "lib/Biblio/bp/lib/bp-output.pl".            |
                                                 |
17. POE::Kernel is listed by M:B as              | I will have to adjust manually
                                                 | and write a bugreport
  POE::Kernel:                                   |
    file: lib/POE/Resource/Signals.pm            |
    version: 1.0013                              |
                                                 |
    As there is a file POE/Kernel.pm that has    |
    a version of 1.0314, the PAUSE indexer       |
    decides that this is what we accept as a     |
    version. As the M:B version is lower, the    |
    indexer cannot accept it                     |
                                                 |
18. M:B accepts 0.2.0 as a version               | I don't.


===========================================================================================

Implementation plan in mldistwatch:

The META_CONTENT key is attached to the PAUSE::dist object. When we
reach the file object with examine_fio, this object lives in
FIO->{DIO}, the dist object.

examine_fio checks a single pmfile and contains the parse_version call
that we are happy to skip, when we have the version from YAML. This
always gave us one version per file.

   examine_fio then parses the file for package statements,
   filter_ppps filters the packages (e.g. the quite important "simile"
   operation and the no_index stuff from the META.yml) and examines
   the found packages in examine_pkg. This part mainly deals with the
   database and permissions and needs to stay intact.

   I'd like to keep as much as possible of this valuable code, because
   I have to control what the YAML provides as much as I can to
   protect against SPAM, violations and mistakes in the YAML file.

=cut
