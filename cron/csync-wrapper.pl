#!/usr/bin/perl

# prevent running more than N processes and log with timestamp and $$ interleaved

# other jobs care for the hints and the collection of dirty files,
# this is only about transfers

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
if (0) {
} elsif ($Opt{update}) {
  $csync_command .= " -cu";
} elsif ($Opt{check}) {
  $csync_command .= " -cr /";
} elsif ($Opt{tuxi}) {
  my($to) = $Opt{tuxi};
  $csync_command .= " -TUXI pause.perl.org $to";
} else {
  die "illegal mode $Opt{mode}";
}
sub timestamp ();
sub logger ($);
sub count_csync_processes ();

my $logfile = "/var/log/csync2.log";

if (count_csync_processes >= 10) {
  logger "csync2 contention, not starting";
  exit;
}

if (my $pid = open my $fh, qq($csync_command 2>&1 |)) {
  logger "Started with pid[$pid] command[$csync_command]";
  local $/ = "\n";
  while (<$fh>) {
    next if /^\s*$/;
    chomp;
    logger $_;
  }
  logger "reached end of output stream";
} else {
  logger "could not fork csync2: $!";
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

sub count_csync_processes () {
  open my $fh, "/bin/ps --no-headers -eo pid,rss,args |" or die "Could not fork ps: $!";
  local $/ = "\n";
  my $count = 0;
  while (<$fh>) {
    next unless m|^\s*(\d+\s)/usr/sbin/csync2\s|;
    $count++;
  }
  $count;
}
