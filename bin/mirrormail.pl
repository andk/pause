#!/usr/bin/perl -w

use lib "/home/k/PAUSE/lib";
use PAUSE ();
use strict;
use Mail::Send;
use DBI;
use vars qw($Id);

$Id = q$Id: mirrormail.pl,v 1.24 1999/08/08 12:51:36 k Exp k $;

my $subject;
my $do_send; # not for symlinks only
my $cc_cpan_testers;
if ($ARGV[0] eq "-s"){
    shift @ARGV;
    $subject = shift @ARGV;
}
#warn "subject[$subject]";

my @argv = @ARGV;

@ARGV = ();

my($stdin,$report,@recipients,$targetdir,$nohash,$send_hash);
{ local $/; $stdin = <STDIN>; }
$send_hash = 1;
$report = "The mirror program running on PAUSE triggered this email.
Please complain if it is not appropriate for some reason.
\tVirtually Yours,
\t$Id\n\n";

for my $line (split /\n/, $stdin) {
    if ( $line =~ m{
		    ^Mirrored\s
		    (\S+)\s                 # userid
		    \(\S+?:\S+\s->\s
		    (\S+)                   # targetdir
		    \)
		   }x ) {
	my($userid) = $1;
	$targetdir = $2;
	$subject .= " $userid";
	$userid =~ s/[a-z]+//g; # throw away lowercase (TOMC_scripts, cpanhtml)
	$userid =~ s/_.*//;     # away underscore and more (TIMB_DBI)
	if ($userid) {
	    my $db;
	    my $query = qq{SELECT *
                           FROM users
                           WHERE userid=?};
	    if ( $db = DBI->connect(
				    $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
				    $PAUSE::Config->{MOD_DATA_SOURCE_USER},
				    $PAUSE::Config->{MOD_DATA_SOURCE_PW},
				    { RaiseError => 1 }
				   )) {
		my $sth = $db->prepare($query);
		$sth->execute($userid);
		if ( $sth->rows > 0 ) {
		    my($hash) = $sth->fetchrow_hashref;
		    push @recipients, qq{"$hash->{fullname}" <$hash->{email}>};
		} else {
		    $report .= "\nWarning: No records found for query
    $query\n";
		}
		$sth->finish;
		$db->disconnect;
	    } else {
		$report .= "\nError: $DBI::errstr\n";
	    }
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
    }
}

push @recipients, $PAUSE::Config->{CPAN_TESTERS} if $cc_cpan_testers;
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
  $msg->add("Reply-To", $PAUSE::Config->{CPAN_TESTERS});
  warn "opening sendmail for $msg\n";
  my $fh  = $msg->open('sendmail');
  print $fh $report, $stdin;
  $fh->close;
} else {
  warn "mirror message seems to be boring: $report";
}
