#!/usr/local/bin/perl -w

# use 5.010;
use strict;
use warnings;

=head1 NAME



=head1 SYNOPSIS



=head1 OPTIONS

=over 8

=cut

my @opt = <<'=back' =~ /B<--(\S+)>/g;

=item B<--debug!>

trace directories and timings etc.

=item B<--help|h!>

This help

=item B<--max=i>

stop running after that many signatures

=item B<--sleep-per-dir=f>

Sleep that amount of time in every directory we enter

=item B<--startdir=s>

start at this directory

=back

=head1 DESCRIPTION



=cut


use FindBin;
use lib "$FindBin::Bin/../lib";

use File::Basename qw(dirname);
use File::Path qw(mkpath);
use File::Spec;
use File::Temp;
use Getopt::Long;
use Hash::Util qw(lock_keys);
use Pod::Usage;

my $lockfile = "/var/run/PAUSE-update-checksums.LCK";
use Fcntl qw( :flock :seek O_RDONLY O_RDWR O_CREAT );
my $lfh;
unless (open $lfh, "+<", $lockfile) {
    open $lfh, ">>", $lockfile or die "Could not open lockfile: $!";
    open $lfh, "+<", $lockfile or die "Could not open lockfile: $!";
}
if (flock $lfh, LOCK_EX|LOCK_NB) {
    warn "Info: Got the lock, continuing";
} else {
    die "lockfile '$lockfile' locked by a different process; cannot continue";
}

our %Opt;
lock_keys %Opt, map { /([^=\|!]+)/ } @opt;
GetOptions(\%Opt,
           @opt,
          ) or pod2usage(1);
if ($Opt{help}) {
    pod2usage(1);
}

use CPAN::Checksums 2.12;
use File::Copy qw(cp);
use File::Find;
use File::Spec;
use Time::HiRes qw(sleep time);
use YAML::Syck;
use strict;

use PAUSE ();

$Opt{debug} ||= 0;
if ($Opt{debug}) {
  warn "Debugging on. CPAN::Checksums::VERSION[$CPAN::Checksums::VERSION]";
}
my $root = $PAUSE::Config->{MLROOT};
$Opt{startdir} //= $root;
our $TESTDIR;

# max: 15 was really slow, 100 is fine, 1000 was temporarily used
# because of key-expiration on 2005-02-02; 1000 also seems appropriate
# now that we know that the process is not faster when we write less
# (2005-11-11); but lower than 1000 helps to smoothen out peaks; 512
# make a lot of noise on the rsyncs (2013-05-06)
$Opt{max} ||= 128;
$Opt{"sleep-per-dir"} ||= 0.5;

my $cnt = 0;

$CPAN::Checksums::CAUTION = 1;
$CPAN::Checksums::SIGNING_PROGRAM =
    "$PAUSE::Config->{CHECKSUMS_SIGNING_PROGRAM} $PAUSE::Config->{CHECKSUMS_SIGNING_ARGS}";
$CPAN::Checksums::SIGNING_KEY =
    $PAUSE::Config->{CHECKSUMS_SIGNING_KEY};
$CPAN::Checksums::MIN_MTIME_CHECKSUMS =
    $PAUSE::Config->{MIN_MTIME_CHECKSUMS} || 0;

find(sub {
       exit if $cnt>=$Opt{max};
       return unless $File::Find::name =~ m{id(/|$)};
       return if -l;
       return unless -d;
       if ($Opt{"sleep-per-dir"}) {
           sleep $Opt{"sleep-per-dir"};
       }
       local($_); # Ouch, has it bitten that the following function
                  # did something with $_. Must have been a bug in 5.00556???

       # we need a way to force updatedir to run an update. If the
       # signature needs to be replaced for some reason. I do not know
       # which reason this will be, but it may happen. Something like
       # $CPAN::Checksums::FORCE_UPDATE?

       my $debugdir;
       my $yaml;
       my $ffname = $File::Find::name;
       if ( $Opt{debug} ) {
         require File::Temp;
         require File::Path;
         require File::Spec;
         $TESTDIR ||= File::Temp::tempdir(
                                          "update-checksums-XXXX",
                                          DIR => "/tmp",
                                          CLEANUP => 0,
                                         ) or die "Could not make a tmp directory";
         my $test_sub_dir = length($ffname) <= length($root)
             ? "Root" : substr($ffname, length($root));
         $debugdir = File::Spec->catdir($TESTDIR,$test_sub_dir);
         File::Path::mkpath($debugdir);
         my $old_checksums = File::Spec->catfile(
                                                 $ffname,
                                                 "CHECKSUMS"
                                                );
         my @stat = stat $old_checksums;
         $yaml->{stat_1} = \@stat;
         my $old_checksums_old =
             File::Spec->catfile($debugdir, "CHECKSUMS.old");
         cp($old_checksums, $old_checksums_old)
             or die "Could not copy '$old_checksums' to ".
             "'$old_checksums_old': $!";
         $yaml->{start} = time;
       }
       my $ret = eval { CPAN::Checksums::updatedir($ffname); };
       if ($@) {
         warn "error[$@] in checksums file[$ffname]: must unlink";
         unlink "$ffname/CHECKSUMS";
       }
       if ($Opt{debug}) {
         my $new_checksums = File::Spec->catfile(
                                                 $ffname,
                                                 "CHECKSUMS"
                                                );
         my @stat = stat $new_checksums;
         $yaml->{stat_2} = \@stat;
         cp($new_checksums,
            File::Spec->catfile($debugdir,
                                "CHECKSUMS.new")
           ) or die $!;
         $yaml->{stop} = time;
         my $tooktime = sprintf "%.6f", $yaml->{stop} - $yaml->{start};
         warn "debugdir[$debugdir]ret[$ret]tooktime[$tooktime]cnt[$cnt]\n";
         $yaml->{tooktime} = $tooktime;
         YAML::Syck::DumpFile(File::Spec->catfile($debugdir,
                                                  "YAML"), $yaml);
       }
       return if $ret == 1;
       my $abs = File::Spec->rel2abs($ffname);
       PAUSE::newfile_hook("$abs/CHECKSUMS");
       $cnt++;
     }, $Opt{startdir});

