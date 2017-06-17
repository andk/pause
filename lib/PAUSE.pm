#!/usr/bin/perl

package PAUSE;

=comment

All the code in here is very old. Many functions are not needed
anymore or at least I am in the process of eliminating dependencies on
it. Before you *use* a function here, please ask about its status.

=cut

# nono for non-CGI: use CGI::Switch ();

use File::Basename ();
use Compress::Zlib ();
use Cwd ();
use DBI ();
use Exporter;
use Fcntl qw(:flock SEEK_SET);
my $HAVE_RECENTFILE = eval {require File::Rsync::Mirror::Recentfile; 1;};
use File::Spec ();
use IO::File ();
use List::Util ();
use Digest::MD5 ();
use Digest::SHA1 ();
use Mail::Send ();
use Sys::Hostname ();
use Time::Piece;
use YAML::Syck;

our $USE_RECENTFILE_HOOKS = Sys::Hostname::hostname =~ /pause/;
if ($USE_RECENTFILE_HOOKS) {
  unless ($HAVE_RECENTFILE) {
    die "Did not find Recentfile library!";
  }
}
our $IS_PAUSE_US = Sys::Hostname::hostname =~ /pause2/ ? 1 : 0;

use strict;
use vars qw(@ISA @EXPORT_OK $VERSION $Config $Id);

@ISA = qw(Exporter); ## no critic
@EXPORT_OK = qw(urecord);

$VERSION = "1.005";
$Id = "PAUSE version $PAUSE::VERSION";

# for Configuration Variable we use PrivatePAUSE.pm, because these are
# really variables we cannot publish. Will separate harmless variables
# from the secret ones and put them here in the future.

my($pauselib) = File::Basename::dirname Cwd::abs_path __FILE__;
{
  my $try = $pauselib;
  $try =~ s|pause/(?:blib/)?lib|pause-private|; # pause2.develooper.com has pause/ and pause-private/
  if (-e $try) { # pause-private is accessible for apache, lib not
    $pauselib = "$try/lib";
  } else {
    $try = $pauselib;
    $try =~ s|/lib|/privatelib|;           # pause.fiz-chemie.de has lib/ and privatelib/
    if (-e $try) {
      $pauselib = $try;
    } else {
      die "Alert: did not find private directory pauselib[$pauselib] try[$try]";
    }
  }
}

push @INC, $pauselib;

$PAUSE::Config ||=
    {
     # previously also used for ftp password; still used in Error as
     # contact address and as address to send internal notifications
     # to:
     FTP_RUN => qq{/home/ftp/run},
     ABRA_EXPIRATION => 86400/4,
     ADMIN => qq{andreas.koenig.gmwojprw+pause\@franz.ak.mind.de},
     ADMINS => [qq(modules\@perl.org)],
     ANON_FTP_PASS => qq{k\@pause.perl.org},
     AUTHEN_DATA_SOURCE_NAME => "DBI:mysql:authen_pause",
     AUTHEN_PASSWORD_FLD => "password",
     AUTHEN_USER_FLD => "user",
     AUTHEN_USER_TABLE => "usertable",
     AUTHEN_BACKUP_DIR => $IS_PAUSE_US
     ? '/home/puppet/pause-var/backup'
     : '/home/k/PAUSE/111_sensitive/backup',
     BZCAT_PATH => (List::Util::first { -x $_ } ("/bin/bzcat", "/usr/bin/bzcat" )),
     BZIP2_PATH => (List::Util::first { -x $_ } ("/bin/bzip2", "/usr/bin/bzip2" )),
     CPAN_TESTERS => qq(cpan-uploads\@perl.org), # cpan-uploads is a mailing list, BINGOS relies on it
     TO_CPAN_TESTERS => qq(cpan-uploads\@perl.org),
     REPLY_TO_CPAN_TESTERS => qq(cpan-uploads\@perl.org),
     DELETES_EXPIRE => 60*60*72,
     FTPPUB => '/home/ftp/pub/PAUSE/',
     GITROOT => '/home/ftp/pub/PAUSE/PAUSE-git',
     GONERS_NOTIFY => qq{gbarr\@search.cpan.org},
     GZIP_OPTIONS => '--best --rsyncable',
     GZIP_PATH => (List::Util::first { -x $_ } ("/bin/gzip", "/usr/bin/gzip" )),
     HOME => $IS_PAUSE_US ? '/home/puppet/' : '/home/k/',
     CRONPATH => $IS_PAUSE_US ? '/home/puppet/pause/cron' : '/home/k/pause/cron',
     HTTP_ERRORLOG => '/usr/local/apache/logs/error_log', # harmless use in cron-daily
     INCOMING => $IS_PAUSE_US ? 'ftp://localhost/incoming/' : 'ftp://pause.perl.org/incoming/',
     INCOMING_LOC => '/home/ftp/incoming/',
     LOG_CALLBACK => sub {
       # $entity: entity from which to grab log configuration
       # $level: level by which logs are filtered
       # @what: messages being logged
       my($entity,$level,@what) = @_;
       unless (@what) {
         @what = ("warning: verbose called without \@what: ", $level);
         $level = 1;
       }
       return if $level > ($entity->{VERBOSE}||0);
       unless (exists $entity->{INTRODUCED}) {
         my $now = scalar localtime;
         require Data::Dumper;
         unshift @what, "Running $0, $Id, $now",
           Data::Dumper->new([$entity],[qw()])->Indent(1)->Useqq(1)->Dump;
         $entity->{INTRODUCED} = undef;
       }
       push @what, "\n" unless $what[-1] =~ m{\n$};
       my $logfh;
       if (my $logfile = $entity->{OPT}{logfile}) {
         open $logfh, ">>", $logfile or die;
         unshift @what, scalar localtime;
       } else {
         $logfh = *STDOUT;
       }
       print $logfh @what;
     },
     MAIL_MAILER => ["sendmail"],
     MAXRETRIES => 16,
     MIRRORCONFIG => '/usr/local/mirror/mymirror.config',
     MIRRORED_BY_URL => "ftp://ftp.funet.fi/pub/languages/perl/CPAN/MIRRORED.BY",
     MLROOT => '/home/ftp/pub/PAUSE/authors/id/', # originally module list root
     ML_CHOWN_USER  => $IS_PAUSE_US ? qq{pause-unsafe} : qq{UNSAFE},
     ML_CHOWN_GROUP => $IS_PAUSE_US ? qq{pause-unsafe} : qq{UNSAFE},
     ML_MIN_INDEX_LINES => 1_000, # 02packages must be this long
     ML_MIN_FILES => 20_000, # must be this many files to run mldistwatch
     MOD_DATA_SOURCE_NAME => "dbi:mysql:mod",
     NO_SUCCESS_BREAK => 900,
     P5P => 'release-announce@perl.org',
     PID_DIR => "/var/run/",
     PAUSE_LOG => $IS_PAUSE_US ? "/var/log/paused.log" : "/home/k/PAUSE/log/paused.log",
     PAUSE_LOG_DIR => $IS_PAUSE_US ? "/var/log" : "/home/k/PAUSE/log/",
     PAUSE_PUBLIC_DATA => '/home/ftp/pub/PAUSE/PAUSE-data',
     PML => 'ftp://pause.perl.org/pub/PAUSE/authors/id/',
     PUB_MODULE_URL => 'http://www.cpan.org/authors/id/',
     RUNDATA => "/usr/local/apache/rundata/pause_1999",
     RUNTIME_MLDISTWATCH => 600, # 720 was the longest of on 2003-08-10,
                                 # 2004-12-xx we frequently see >20 minutes
                                 # 2006-05-xx 7-9 minutes observed
     SLEEP => 75,
     TIMEOUT => 60*60,
     TMP => '/home/ftp/tmp/',
     UPLOAD => 'upload@pause.perl.org',
     # sign the auto-generated CHECKSUM files with:
     CHECKSUMS_SIGNING_PROGRAM => ('gpg'),
     CHECKSUMS_SIGNING_ARGS => '--homedir /home/puppet/pause-private/gnupg-pause-batch-signing-home --clearsign --default-key ',
     CHECKSUMS_SIGNING_KEY => '450F89EC',
     BATCH_SIG_HOME => "/home/puppet/pause-private/gnupg-pause-batch-signing-home",
     MIN_MTIME_CHECKSUMS => 1300000000, # invent a threshold for oldest mtime
     HAVE_PERLBAL => 1,
     ZCAT_PATH  => (List::Util::first { -x $_ } ("/bin/zcat", "/usr/bin/zcat" )),
    };

unless ($INC{"PrivatePAUSE.pm"}) { # reload within apache
  eval { require PrivatePAUSE; };
  if ($@) {
    if ($0 =~ /^(stamp|-e)$/) {
      # PAUSE.pm is used in the timestamp cronjob without access to
      # privatelib; cannot warn every minute warn "Could not find or
      # read PrivatePAUSE.pm; will try to work without";
    } else {
      warn "Warning (continuing anyway): $@";
    }
  }
}

=pod

The following $PAUSE::Config keys are defined in PrivatePAUSE.pm:

              AUTHEN_DATA_SOURCE_USER
              AUTHEN_DATA_SOURCE_PW
              MOD_DATA_SOURCE_USER
              MOD_DATA_SOURCE_PW

These are usernames and passwords in the two mysql databases.

=cut


=over

=item downtimeinfo

returns a hashref with keys C<downtime> and C<willlast>. C<downtime>
is an integer denoting the system time (measured in epoch seconds) of
the next downtime event. C<willlast> is an integer measuring seconds.

If the downtime is in the future, we display an announcement on all
pages. If we are now in the interval between the start of the downtime
and the expected end, we display a trivial page saying I<closed for
maintainance> while returning a 500 Server Error. This even works when
mysql is not running (server error + custom response). Interestingly,
it does not work if the user does not supply credentials at all.

If current time is after the last downtime event plus scheduled
downtime, then we're back to normal operation.

Hint: I like to use date to determine a timestamp in the future

   % date +%s --date="Mon Dec 31 15:00:00 UTC 2012"

=back

=cut

sub downtimeinfo {
  return $IS_PAUSE_US ? +{
                          downtime => 1357374600,
                          willlast => 5400,
                         }
      : +{
          downtime => 1357374600,
          willlast => 5400,
         };
}

sub filehash {
  my($file) = @_;
  my($ret,$authorfile,$size,$md5,$sha1,$hexdigest,$sha1hexdigest);
  $ret = "";
  if (substr($file,0,length($Config->{MLROOT})) eq $Config->{MLROOT}) {
    $authorfile = "\$CPAN/authors/id/" .
    substr($file,length($Config->{MLROOT}));
  } else {
    $authorfile = $file;
  }
  $size = -s $file;
  $md5 = Digest::MD5->new;
  $sha1 = Digest::SHA1->new;
  local *HANDLE;
  unless ( open HANDLE, "< $file\0" ){
    $ret .= "An error occurred, couldn't open $file: $!"
  }
  $md5->addfile(*HANDLE);
  seek(HANDLE, SEEK_SET, 0);
  $sha1->addfile(*HANDLE);
  close HANDLE;
  $hexdigest = $md5->hexdigest;
  $sha1hexdigest = $sha1->hexdigest;
  $ret .= qq{
  file: $authorfile
  size: $size bytes
   md5: $hexdigest
  sha1: $sha1hexdigest
};
  return $ret;
}

sub log {
    my ($self, @arg) = @_;
    $PAUSE::Config->{LOG_CALLBACK}->(@arg);
}

sub dbh {
  my($db) = shift || "mod";
  my $dsn = $PAUSE::Config->{uc($db)."_DATA_SOURCE_NAME"};
  my $dbh = DBI->connect(
               $dsn,
               $PAUSE::Config->{uc($db)."_DATA_SOURCE_USER"},
               $PAUSE::Config->{uc($db)."_DATA_SOURCE_PW"},
               { RaiseError => 1 }
              )
      or Carp::croak(qq{Can't DBI->connect(): $DBI::errstr});

  if ($dsn =~ /^DBI:mysql:/) {
    $dbh->do("SET sql_mode='STRICT_TRANS_TABLES'")
      or Carp::croak(qq{Can't DBI->connect(): $DBI::errstr});
  }

  return $dbh;
}

sub urecord {
  my($ruser) = @_;
  return unless $ruser;
  my $db = dbh("mod");
  my $query = qq{SELECT *
                 FROM users
                 WHERE userid=?};
  my $sth = $db->prepare($query);
  $sth->execute($ruser);
  if ($sth->rows == 0) {
    $sth->execute(uc $ruser);
  }
  $sth->fetchrow_hashref;
}

sub user2dir {
  my($user) = @_;
  my(@l) = $user =~ /^(.)(.)/;
  my $result = "$l[0]/$l[0]$l[1]/$user";
  if (
      -d "$PAUSE::Config->{MLROOT}/$user"
      && !
      -d "$PAUSE::Config->{MLROOT}/$result"
     ) {
    $result = $user;
  }
  $result;
}

# available as pause_1999::main::file_to_user method
sub dir2user {
  my($uriid) = @_;
  $uriid =~ s|^/?authors/id||;
  $uriid =~ s|^/||;
  my $ret;
  if ($uriid =~ m|^\w/| ) {
    ($ret) = $uriid =~ m|\w/\w\w/([^/]+)/|;
  } else {
    ($ret) = $uriid =~ m!(.*?)/!;
  }
  $ret;
}

sub user_is {
  my($class,$user,$group) = @_;
  my $db = dbh("authen");
  my $ret;
  my $sth = $db->prepare(qq{
    SELECT ugroup FROM grouptable WHERE user='$user' AND ugroup='$group'
  });
  $ret = $sth->execute;
  return unless $ret;
  $ret = $sth->rows;
  $sth->finish;
  $db->disconnect;
  return $ret;
}

# must be case-insensitive
sub owner_of_module {
    my($m, $dbh) = @_;
    $dbh ||= dbh();
    my %query = (
                 mods => qq{SELECT modid,
                          userid
                   FROM mods where modid = ?},
                 primeur => qq{SELECT package,
                          userid
                   FROM primeur where LOWER(package) = LOWER(?)},
                );
    for my $table (qw(mods primeur)) {
        my $owner = $dbh->selectrow_arrayref($query{$table}, undef, $m);
        return $owner->[1] if $owner;
    }
    return;
}

sub gzip {
  my($read,$write) = @_;
  my($buffer,$fhw);
  unless ($fhw = IO::File->new($read)) {
    warn("Could not open $read: $!");
    return;
  }
  my $gz;
  unless ($gz = Compress::Zlib::gzopen($write, "wb9")) {
    warn("Cannot gzopen $write: $!\n");
    return;
  }
  $gz->gzwrite($buffer)
      while read($fhw,$buffer,4096) > 0 ;
  $gz->gzclose() ;
  $fhw->close;
  return 1;
}

sub gunzip {
  my($read,$write) = @_;
  unless ($write) {
    warn "gunzip called without write argument";
    warn join ":", caller;
    warn "nothing done";
    return;
  }

  my($buffer,$fhw);
  unless ($fhw = IO::File->new(">$write\0")) {
    warn("Could not open >$write: $!");
    return;
  }
  my $gz;
  unless ($gz = Compress::Zlib::gzopen($read, "rb")) {
    warn("Cannot gzopen $read: $!\n");
    return;
  }
  $fhw->print($buffer)
      while $gz->gzread($buffer) > 0 ;
  if ($gz->gzerror != &Compress::Zlib::Z_STREAM_END) {
    warn("Error reading from $read: $!\n");
    return;
  }
  $gz->gzclose() ;
  $fhw->close;
  return 1;
}

sub gtest {
  my($class,$read) = @_;
  my($buffer);
  my $gz;
  unless (
    $gz = Compress::Zlib::gzopen($read, "rb")
  ) {
    warn("Cannot open $read: $!\n");
    return;
  }
  1 while $gz->gzread($buffer) > 0 ;
  if ($gz->gzerror != &Compress::Zlib::Z_STREAM_END) {
    warn("Error reading from $read: $!\n");
    return;
  }
  $gz->gzclose() ;
  return 1;
}

# log4perl!
#sub hooklog {
#  my($f) = @_;
#  open my $fh, ">>", "/tmp/hook.log";
#  use Carp;
#  printf $fh "%s: %s [%s]\n", scalar localtime, $f, Carp::longmess();
#}

our @common_args =
    (
     canonize => "naive_path_normalize",
     interval => q(1h),
     filenameroot => "RECENT",
     protocol => 1,
     comment => "These files are part of the CPAN mirroring concept, described in File::Rsync::Mirror::Recent",
    );

sub newfile_hook {
  return unless $USE_RECENTFILE_HOOKS;
  my($f) = @_;
  my $rf;
  eval {
    $rf = File::Rsync::Mirror::Recentfile->new
        (
         @common_args,
         localroot => "/home/ftp/pub/PAUSE/authors/",
         aggregator => [qw(6h 1d 1W 1M 1Q 1Y Z)],
        );
  };
  unless ($rf) {
    warn "ALERT: Could not create an rf: $@";
    return;
  }
  $rf->update($f,"new");
  $rf = File::Rsync::Mirror::Recentfile->new
      (
       @common_args,
       localroot => "/home/ftp/pub/PAUSE/modules/",
       aggregator => [qw(1d 1W Z)],
      );
  $rf->update($f,"new");
}

sub delfile_hook {
  return unless $USE_RECENTFILE_HOOKS;
  my($f) = @_;
  my $rf;
  eval {
    $rf = File::Rsync::Mirror::Recentfile->new
        (
         @common_args,
         localroot => "/home/ftp/pub/PAUSE/authors/",
         aggregator => [qw(6h 1d 1W 1M 1Q 1Y Z)],
        );
  };
  unless ($rf) {
    warn "ALERT: Could not create an rf: $@";
    return;
  }
  $rf->update($f,"delete");
  $rf = File::Rsync::Mirror::Recentfile->new
      (
       @common_args,
       localroot => "/home/ftp/pub/PAUSE/modules/",
       aggregator => [qw(1d 1W Z)],
      );
  $rf->update($f,"delete");
}

sub _time_string {
  my ($self, $s) = @_;
  my $time = Time::Piece->new($s);
  return join q{ }, $time->ymd, $time->hms;
}

sub _now_string {
  my ($self) = @_;
  return $self->_time_string(time);
}

sub user_has_pumpking_bit {
  my ($self, $user) = @_;

  use DBI;
  my $adbh = DBI->connect(
    $PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME},
    $PAUSE::Config->{AUTHEN_DATA_SOURCE_USER},
    $PAUSE::Config->{AUTHEN_DATA_SOURCE_PW},
  ) or die $DBI::errstr;

  my ($ok) = $adbh->selectrow_array(
    "SELECT COUNT(*) FROM grouptable WHERE user= ? AND ugroup='pumpking'",
    undef,
    $user,
  );

  $adbh->disconnect;

  return $ok;
}

1;

# Local Variables:
# mode: cperl
# cperl-indent-level: 2
# End:
