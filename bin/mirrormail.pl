#!/usr/local/bin/perl -w

=pod

This program is triggered by mirror. It is configured to be run in
mirror/mirror.defaults. It receives a report for a single mirror
package (e.g. MUIR) on STDIN. mirror is started by cron/run_mirrors.sh
and receives the same output and as such it is sent by cron to the
admin.

This program does the additional work of providing feedback for all
interested parties: the author, the testers and the admin in case of
an alert.

=cut

use FindBin;
use lib "$FindBin::Bin/../lib";
use PAUSE ();
use strict;
use Mail::Send;
use DBI;

my $subject;
my $do_send         = 0; # not for symlinks only
my $cc_cpan_testers = 0;
my $to_cpan_admin   = 0;

if ($ARGV[0] eq "-s"){
    shift @ARGV;
    $subject = shift @ARGV;
}
warn "subject[$subject]";

my @argv = @ARGV;

@ARGV = ();

my($stdin,$report,@recipients,$sourcedir,$targetdir,$send_hash);
{ local $/; $stdin = <STDIN>; }
$send_hash = 1;
$report = "The mirror program running on PAUSE triggered this email.
Please complain if it is not appropriate for some reason.

Thanks,
\n\n";

for my $line (split /\n/, $stdin) {
  if ( $line =~ m{
                  ^Mirrored\s
                  (\S+)\s                 # userid
                  \((\S+?:\S+)\s->\s      # sourcedir
                  (\S+)                   # targetdir
                  \)
                }x ) {
    my($userid) = $1;
    $sourcedir = $2;
    $targetdir = $3;
    $subject .= " $userid";
    $userid =~ s/[a-z]+//g; # throw away lowercase (TOMC_scripts, cpanhtml)
    $userid =~ s/_.*//;     # away underscore and more (TIMB_DBI)
    if ($userid) {
      push @recipients, qq{<$userid\@cpan.org>};
    } else {
      $report .= "DEBUG: userid[$userid]\n";
      $send_hash = 0;
    }
  } elsif (
           $send_hash && $line =~ /^Got \S+ as (\S+)/ 
           ||
           $send_hash && $line =~ /^Got (\S+)/
          ) {
    my $file = $1;
    $report .= PAUSE::filehash("$targetdir/$file");
    $do_send++;
    $cc_cpan_testers++;
  } elsif ($line =~ /^Failed/) {
    # $subject .= " ALERT";
    my($src_path) = $line =~ /src_path\[(.+?)\]/;
    $to_cpan_admin++;
    $do_send++;
    $cc_cpan_testers = 0;
    my($host,$lower_path) = $sourcedir =~ /^(.+?):(.+)$/;
    my($local_abs) = "$targetdir/$src_path";
    require File::Basename;
    my($local_dir) = File::Basename::dirname($local_abs);
    require File::Path;
    File::Path::mkpath($local_dir);
    my($remote_abs) = "$lower_path$src_path";
    warn "src_path[$src_path]
sourcedir[$sourcedir]
targetdir[$targetdir]
stdin[$stdin]
local_dir[$local_dir]
local_abs[$local_abs]
remote_abs[$remote_abs]\n\n";
    require Net::FTP;
    my $ftp = Net::FTP->new($host);
    $ftp->login("ftp","k\@");
    $ftp->get($remote_abs, $local_abs);
    # $report .= sprintf "Local file size now: %d\n\n", -s $local_abs;
    $report .= PAUSE::filehash($local_abs);
  }
}

push @recipients, $PAUSE::Config->{CPAN_TESTERS} if $cc_cpan_testers;
push @recipients, $PAUSE::Config->{ADMIN} if $to_cpan_admin;
$report .= "\n";

if ($do_send) {
  my $msg = Mail::Send->new(
			    To => join(
				       ",",
				       @argv,
				       @recipients
				      ),
			    Subject => "CPAN mirror: $subject"
			   );
  $msg->add("From", "PAUSE <$PAUSE::Config->{UPLOAD}>");
  $msg->add("Reply-To", $PAUSE::Config->{CPAN_TESTERS})
      if $cc_cpan_testers;
  warn "opening sendmail for $msg\n";
  my $fh  = $msg->open('sendmail');
  print $fh $report, $stdin;
  $fh->close;
} else {
  warn "\nMirror message seems to be boring report[$report]stdin[$stdin]";
}
