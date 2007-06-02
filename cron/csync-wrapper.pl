#!/usr/bin/perl

# $HeadURL$
# $Id$

# prevent running more than N processes and log with timestamp and $$ interleaved

# other jobs care for the hints and the collection of dirty files,
# this is only about transfers

# TODO: differentiate the running csync2 processes: every host that is
# still being dealt with in a running job should be removed from the
# lot. For the other hosts we can always start a new process. The
# problem is that we do not know the exact plans of the running jobs,
# so if job J1 is currently updating file F1 on host H1, we would
# rotate H1 out of the pool but in a few seconds maybe J1 tries to
# transfer file FX to host H2 and we maybe try the same thing in a few
# seconds. So maybe we have to kill running processes? But how long
# should we wait before killing? This is a nontrivial scheduling task.
# So for now we set the number of -cu processes to a max of 2 and
# allow two processes to try the same file to the same host.

# I think we should try this: one cfg file per host and only one
# running csync2 job per host. Or this: if there is no other -cu job
# running, let csync2 work as it is designed. If there is a running
# job, try to differentiate???

# Small talk with Slaven and I came to the conclusion that this is
# really something that should be handled by csync2 or librsync.

use strict;
use Getopt::Long;
our %Opt;
GetOptions(\%Opt,
           "update!",
           "check!",
           "tuxi=s",
          );
$Opt{update}++ unless %Opt;

my $csync_command =
    q(/usr/sbin/csync2 -B -v -G pause_perl_org -N pause.perl.org);

sub timestamp ();
sub logger ($);
sub csync_processes ();

if (0) {
} elsif ($Opt{update}) {
  my $cp = csync_processes;
  if (@$cp >= 1) {
    logger "EOJ: running csync2 processes[@$cp], not starting";
    exit;
  }
  $csync_command .= " -cu";
} elsif ($Opt{check}) {
  $csync_command .= " -cr /";
} elsif ($Opt{tuxi}) {
  my($to) = $Opt{tuxi};
  $csync_command .= " -TUXI pause.perl.org $to";
} else {
  die "illegal mode $Opt{mode}";
}

my $logfile = "/var/log/csync2.log";

if (my $pid = open my $fh, qq($csync_command 2>&1 |)) {
  logger "Started with pid[$pid] command[$csync_command]";
  local $/ = "\n";
  while (<$fh>) {
    next if /^\s*$/;
    chomp;
    logger $_;
  }
  logger "EOJ: reached end of output stream";
} else {
  logger "EOJ: could not fork csync2: $!";
}

sub timestamp () {
  my $time = time;
  our($last_str,$last_time);
  return $last_str if $last_time and $time == $last_time;
  my($sec,$min,$hour,$mday,$mon,$year)
      = localtime($last_time = $time);
  $last_str = sprintf("%04d-%02d-%02d %02u:%02u:%02u",
		      $year+1900,$mon+1,$mday, $hour,$min,$sec);
}

sub logger ($) {
  my($arg) = @_;
  my $stamp = timestamp();
  open my $log, ">>", $logfile or die "open $logfile: $!";
  print $log "$stamp $$ $arg\n";
  close $log;
}

sub csync_processes () {
  open my $fh, "/bin/ps --no-headers -eo pid,rss,args |" or die "Could not fork ps: $!";
  local $/ = "\n";
  my @c;
  while (<$fh>) {
    next unless m|^\s*(\d+)\s+\d+\s+/usr/sbin/csync2.*-cu|;
    push @c, $1;
  }
  \@c;
}
