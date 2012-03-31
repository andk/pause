#!/usr/bin/perl

package PAUSE;

=comment

All the code in here is very old. Many functions are not needed
anymore or at least I am in the process of eliminating dependencies on
it. Before you *use* a function here, please ask about its status.

=cut

# nono for non-CGI: use CGI::Switch ();

use Compress::Zlib ();
use DBI ();
use Exporter;
use Fcntl qw(:flock);
my $HAVE_RECENTFILE = eval {require File::Rsync::Mirror::Recentfile; 1;};
use File::Spec ();
use IO::File ();
use MD5 ();
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


use strict;
use vars qw(@ISA @EXPORT_OK $VERSION $Config);

@ISA = qw(Exporter); ## no critic
@EXPORT_OK = qw(urecord);

$VERSION = "1.005";

# for Configuration Variable we use PrivatePAUSE.pm, because these are
# really variables we cannot publish. Will separate harmless variables
# from the secret ones and put them here in the future.

my(@pauselib) = grep m!(/PAUSE|\.\.|/SVN)/lib!, @INC;
for (@pauselib) {
  s|/lib|/privatelib|;
}
push @INC, @pauselib;
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
     CPAN_TESTERS => qq(cpan-uploads\@perl.org), # cpan-uploads is a mailing list, BINGOS relies on it
     TO_CPAN_TESTERS => qq(cpan-uploads\@perl.org),
     REPLY_TO_CPAN_TESTERS => qq(cpan-uploads\@perl.org),
     DELETES_EXPIRE => 60*60*72,
     FTPPUB => '/home/ftp/pub/PAUSE/',
     GITROOT => '/home/ftp/pub/PAUSE/PAUSE-git',
     GONERS_NOTIFY => qq{gbarr\@search.cpan.org},
     GZIP => '/bin/gzip',
     GZIP_OPTIONS => '--best --rsyncable',
     HOME => '/home/k/',
     HTTP_ERRORLOG => '/usr/local/apache/logs/error_log',
     INCOMING => 'ftp://pause.perl.org/incoming/',
     INCOMING_LOC => '/home/ftp/incoming/',
     MAXRETRIES => 16,
     MIRRORCONFIG => '/usr/local/mirror/mymirror.config',
     MLROOT => '/home/ftp/pub/PAUSE/authors/id/', # originally module list root
     ML_CHOWN_USER => qq{UNSAFE},
     ML_CHOWN_GROUP => qq{UNSAFE},
     ML_MIN_INDEX_LINES => 1_000, # 02packages must be this long
     ML_MIN_FILES => 20_000, # must be this many files to run mldistwatch
     MOD_DATA_SOURCE_NAME => "dbi:mysql:mod",
     NO_SUCCESS_BREAK => 900,
     P5P => 'release-announce@perl.org',
     PID_DIR => "/var/run/",
     PAUSE_LOG => "/home/k/PAUSE/log/paused.log",
     PAUSE_LOG_DIR => "/home/k/PAUSE/log/",
     PAUSE_PUBLIC_DATA => '/home/ftp/pub/PAUSE/PAUSE-data',
     PML => 'ftp://pause.perl.org/pub/PAUSE/authors/id/',
     RUNDATA => "/usr/local/apache/rundata/pause_1999",
     RUNTIME_MLDISTWATCH => 600, # 720 was the longest of on 2003-08-10,
                                 # 2004-12-xx we frequently see >20 minutes
                                 # 2006-05-xx 7-9 minutes observed
     SLEEP => 75,
     # path to repository without "/trunk"
     SVNPATH => "/home/SVN/repos",
     # path to where we find the svn binaries
     SVNBIN => "/usr/bin",
     TIMEOUT => 60*60,
     TMP => '/home/ftp/tmp/',
     UPLOAD => 'upload@pause.perl.org',
     # sign the auto-generated CHECKSUM files with:
     CHECKSUMS_SIGNING_PROGRAM => ('gpg'),
     CHECKSUMS_SIGNING_ARGS => ('--homedir /home/k/PAUSE/111_sensi'.
                                   'tive/gnupg-pause-batch-signing-home  '.
                                   '--clearsign --default-key '),
     CHECKSUMS_SIGNING_KEY => '450F89EC',
     BATCH_SIG_HOME => '/home/k/PAUSE/111_sensitive/gnupg-pause-batch-signing-home',
     MIN_MTIME_CHECKSUMS => (time - 60*60*24*365.25), # max one year old
     HAVE_PERLBAL => 1,
    };


eval { require PrivatePAUSE; };
if ($@) {
  # PAUSE.pm is used in the timestamp cronjob without access to privatelib; cannot warn every minute
  # warn "Could not find or read PrivatePAUSE.pm; will try to work without";
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

=back

=cut

sub downtimeinfo {
  return +{
           downtime => 1197317508,
           willlast => 0,
          };
}

sub filehash {
  my($file) = @_;
  my($ret,$authorfile,$size,$md5,$hexdigest);
  $ret = "";
  if (substr($file,0,length($Config->{MLROOT})) eq $Config->{MLROOT}) {
    $authorfile = "\$CPAN/authors/id/" .
    substr($file,length($Config->{MLROOT}));
  } else {
    $authorfile = $file;
  }
  $size = -s $file;
  $md5 = MD5->new;
  local *HANDLE;
  unless ( open HANDLE, "< $file\0" ){
    $ret .= "An error occurred, couldn't open $file: $!"
  }
  $md5->addfile(*HANDLE);
  close HANDLE;
  $hexdigest = $md5->hexdigest;
  $ret .= qq{
  file: $authorfile
  size: $size bytes
   md5: $hexdigest
};
  return $ret;
}

sub dbh {
  my($db) = shift || "mod";
  my $dsn = $PAUSE::Config->{uc($db)."_DATA_SOURCE_NAME"};
  warn "DEBUG: dsn[$dsn]";
  DBI->connect(
               $dsn,
               $PAUSE::Config->{uc($db)."_DATA_SOURCE_USER"},
               $PAUSE::Config->{uc($db)."_DATA_SOURCE_PW"},
               { RaiseError => 1 }
              )
      or Carp::croak(qq{Can't DBI->connect(): $DBI::errstr});
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

sub owner_of_module {
    my($m, $dbh) = @_;
    $dbh ||= dbh();
    my %query = (
                 mods => qq{SELECT modid,
                          userid
                   FROM mods where modid = ?},
                 primeur => qq{SELECT package,
                          userid
                   FROM primeur where package = ?},
                );
    for my $table (qw(mods primeur)) {
        my $sth = $dbh->prepare($query{$table});
        $sth->execute($m);
        if ($sth->rows >= 1) {
            return $sth->fetchrow_array; # ascii guaranteed
        }
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

1;

# Local Variables:
# mode: cperl
# cperl-indent-level: 2
# End:
