#!/usr/bin/perl
#

use strict;
use Date::Parse;

use constant SLICE => 3600;
use constant BYTE_LIMIT_PER_HOUR => 20_000_000;
my(%S,%N,$danger);
my $report = "";

open P, "<", "/var/log/mail/mail.log" or die "Could not open mail.log: $!";
while (<P>){
  my($t,$s) = /^(\S+\s+\S+\s+\S+)\s+\S+\s+sm-mta\[\d+\]:.*size=(\d+)/ or next;
  my $tep = Date::Parse::str2time($t);
  $tep = int($tep/SLICE)*SLICE;
  $N{$tep}++;
  $S{$tep} += $s;
}
close P or die "Could not close P";
for my $t (sort { $a <=> $b } keys %S){
  $report .= sprintf "%s %9d %9d", scalar(localtime $t), $N{$t}, $S{$t};
  if ($S{$t} > SLICE * BYTE_LIMIT_PER_HOUR / 3600) {
    $report .= " <----- ALARM";
    $danger = 1;
  }
  $report .= "\n";
}
my $statsfile = "/var/run/mail-stats-log/alert.txt";
open P, ">", $statsfile or die "Could not open $statsfile: $!";
print P $report;
close P or die "Could not close $statsfile: $!\n\nThe report:\n\n$report";
if ($danger){
  die $report;
}


__END__


=pod

20:50:42 root@pause:~irc/log/mail# perl -nle '
use Date::Parse;BEGIN{$slice = 3600}
my($t,$s) = /^(\S+\s+\S+\s+\S+)\s+\S+\s+sm-mta\[\d+\]:.*size=(\d+)/ or next;
my $tep = Date::Parse::str2time($t);
$tep = int($tep/$slice)*$slice;
$N{$tep}++;
$S{$tep} += $s;
END{
 for my $t (sort keys %S){
  printf "%s %9d %9d\n", scalar(localtime $t), $N{$t}, $S{$t};
 }
}
' mail.log
Sun Aug 24 06:00:00 2003         7    220035
Sun Aug 24 07:00:00 2003        60   2038884
Sun Aug 24 08:00:00 2003        58   1762710
Sun Aug 24 09:00:00 2003        53   2033311
Sun Aug 24 10:00:00 2003        73   1682174
Sun Aug 24 11:00:00 2003        91   2417755
Sun Aug 24 12:00:00 2003        43   1314171
Sun Aug 24 13:00:00 2003        57   1169440

=cut
