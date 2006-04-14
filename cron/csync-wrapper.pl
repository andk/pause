#!/usr/bin/perl

# prevent running more than N processes and log with timestamp and $$ interleaved

# other jobs care for the hints and the collection of dirty files,
# this is only about transfers

use strict;

my $logfile = "/var/log/csync2.log";

if (count_csync_processes >= 10) {
  logger "csync2 contention, not starting";
  exit;
}

if (my $pid = open my $fh, q(/usr/sbin/csync2 -B -u -v -G pause_perl_org -N pause.perl.org 2>&1 |)) {
  logger "Started csync2 with pid[$pid]";
  local $/ = "\n";
  while (<$fh>) {
    logger $_;
  }
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
    next unless m|^\s*\d+\s/usr/sbin/csync2\s|;
    $count++;
  }
  $count;
}
