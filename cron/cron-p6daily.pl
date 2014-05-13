#!/usr/local/bin/perl -w

use FindBin;
use lib "$FindBin::Bin/../lib";
use PAUSE ();

use File::Basename ();
use DBI;
use Mail::Send     ();
use File::Find     ();
use FileHandle     ();
use File::Copy     ();
use HTML::Entities ();
use IO::File       ();
use strict;
use vars qw( $last_str $last_time $SUBJECT @listing $Dbh);

#
# Initialize
#

my $zcat = $PAUSE::Config->{ZCAT_PATH};
die "no executable zcat" unless -x $zcat;
my $gzip = $PAUSE::Config->{GZIP_PATH};
die "no executable gzip" unless -x $gzip;

sub report;

my (@blurb, %fields);
unless (
  $Dbh = DBI->connect(
    $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
    $PAUSE::Config->{MOD_DATA_SOURCE_USER},
    $PAUSE::Config->{MOD_DATA_SOURCE_PW},
    { RaiseError => 1 }
  )
  )
{
  report "Connect to database not possible: $DBI::errstr\n";
}

my $error;
$error = p6dists()    and report $error;
$error = p6provides() and report $error;
$error = p6binaries() and report $error;

send_the_mail();

exit;

#
# Send the mail end leave me alone
#

sub send_the_mail {
  $SUBJECT ||= "cron-p6daily.pl";
  my $MSG = Mail::Send->new(
    Subject => $SUBJECT,
    To      => $PAUSE::Config->{ADMIN}
  );
  $MSG->add("From", "cron daemon cron-p6daily.pl <upload>");
  my $FH = $MSG->open('sendmail');
  print $FH join "", @blurb;
  $FH->close;
}

sub p6dists {
  # Rewriting p6dists.json
  my $repfile = "$PAUSE::Config->{MLROOT}/../p6dists.json.gz";
  my $olist   = _read_file($repfile);
  my $dists   = $Dbh->selectall_arrayref(
    "SELECT name, auth, ver, tarball FROM p6dists ORDER BY tarball"
  );

  # Strip newlines and double quotes, then sort by tarball.
  @$dists = sort { $a->[3] cmp $b->[3] } _clean(@$dists);

  # Transform into JSON snippets, row by row.
  my $p6dist = '
	"%s" : {
		"name" : "%s",
		"auth" : "%s",
		"ver"  : "%s"
	}';
  my @json_rows = map { sprintf($p6dist, @$_[3], @$_[0..2]) } @$dists;

  # Create the JSON document.
  my $list = sprintf("\{\n%s\n\}", join(",", @json_rows));

  my $err = _write_file($repfile, $list) if $list ne $olist;
  return $err if $err;
  PAUSE::newfile_hook($repfile);
  return
}

sub p6provides {
  # Rewriting p6provides.json
  my $repfile  = "$PAUSE::Config->{MLROOT}/../p6provides.json.gz";
  my $olist    = _read_file($repfile);
  my $provides = $Dbh->selectall_arrayref(
    "SELECT name, tarball FROM p6provides ORDER BY name"
  );

  # Strip newlines and double quotes, then create a name-to-tarballs hash.
  @$provides = _clean(@$provides);
  my %name2tarballs;
  push @{$name2tarballs{@$_[0]}}, @$_[1] for @$provides;

  # Transform into JSON snippets, row by row.
  my @json_rows = map { sprintf("	\"%s\" : [%s\n\t]", $_,
    join(",", map { "\n\t\t\"$_\"" } sort @{$name2tarballs{$_}})) } keys %name2tarballs;

  # Create the JSON document.
  my $list = sprintf("\{\n%s\n\}", join(",\n", @json_rows));

  my $err = _write_file($repfile, $list) if $list ne $olist;
  return $err if $err;
  PAUSE::newfile_hook($repfile);
  return
}

sub p6binaries {
  # Rewriting p6binaries.json
  my $repfile  = "$PAUSE::Config->{MLROOT}/../p6binaries.json.gz";
  my $olist    = _read_file($repfile);
  my $binaries = $Dbh->selectall_arrayref(
    "SELECT name, tarball FROM p6binaries ORDER BY name"
  );

  # Strip newlines and double quotes, then create a name-to-tarballs hash.
  @$binaries = _clean(@$binaries);
  my %name2tarballs;
  push @{$name2tarballs{@$_[0]}}, @$_[1] for @$binaries;

  # Transform into JSON snippets, row by row.
  my @json_rows = map { sprintf("	\"%s\" : [%s\n\t]", $_,
    join(",", map { "\n\t\t\"$_\"" } sort @{$name2tarballs{$_}})) } keys %name2tarballs;

  # Create the JSON document.
  my $list = sprintf("\{\n%s\n\}", join(",\n", @json_rows));

  my $err = _write_file($repfile, $list) if $list ne $olist;
  return $err if $err;
  PAUSE::newfile_hook($repfile);
  return
}

sub _clean {
  # Takes a list or array refs, turns utf8 on and strips problematic chars from all fields.
  my @list = @_;
  for my $row (@list) {
    if ($] > 5.007) {
      require Encode;
      for (@$row) {
        /\P{ASCII}/ && Encode::_utf8_on($_);
        s/[\r\n\t"]//g
      }
    }
  }
  @list
}

sub _read_file {
  # Reads a gzipped file and returns its content.
  my $repfile = shift;
  my $olist   = '';
  local ($/)  = undef;
  if (open F, "$zcat $repfile|") {
    if ($] > 5.007) {
      binmode F, ":utf8";
    }
    $olist = <F>;
    close F;
  }
  $olist
}

sub _write_file {
  # Writes a string to a gzipped file.
  my ($repfile, $list) = @_;
  if (open F, "| $gzip -9c > $repfile") {
    if ($] > 5.007) {
      binmode F, ":utf8";
    }
    print F $list;
    close F or return "ERROR: error closing $repfile: $!";
  } else {
    return "ERROR: Couldn't open $repfile to write: $!";
  }
  return
}

sub report {
  my (@rep) = @_;
  push @blurb, @rep;
}
