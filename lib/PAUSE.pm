#!/usr/bin/perl

package PAUSE;

=comment

All the code in here is very old. Many functions are not needed
anymore or at least I am in the process of eliminating dependencies on
it. Before you *use* a function here, please ask about its status.

=cut

# nono for non-CGI: use CGI::Switch ();

use Compress::Zlib ();
use Exporter;
use IO::File ();
use MD5 ();
use Mail::Send ();
use DBI ();

use strict;
use vars qw(@ISA @EXPORT_OK $VERSION $Config);

@ISA = qw(Exporter);
@EXPORT_OK = qw(urecord);

$VERSION = substr q$Revision: 1.60 $, 10;

# for Configuration Variable we use PrivatePAUSE.pm, because these are
# really variables we cannot publish. Will separate harmless variables
# from the secret ones and put them here in the future.

my(@pauselib) = grep m!(/PAUSE|\.\.)/lib!, @INC;
for (@pauselib) {
  s|/lib|/privatelib|;
}
push @INC, @pauselib;
$PAUSE::Config ||=
    {
     # previously also used for ftp password:
     ADMIN => qq{k@localhost},
     ADMINS => [qq(modules\@perl.org)],
     # only dubravka.kbx.de is reverse mapped:
     ANON_FTP_PASS => qq{andreas.koenig\@dubravka.kbx.de},
     AUTHEN_DATA_SOURCE_NAME => "DBI:mysql:authen_pause",
                    AUTHEN_PASSWORD_FLD => "password",
                    AUTHEN_USER_FLD => "user",
                    AUTHEN_USER_TABLE => "usertable",
                    CPAN_TESTERS => qq(cpan-testers\@perl.org),
                    DELETES_EXPIRE => 60*60*72,
                    FTPPUB => '/home/ftp/pub/PAUSE/',
                    GONERS_NOTIFY => qq{gbarr\@search.cpan.org},
                    GZIP => '/bin/gzip',
                    HOME => '/home/k/',
                    HTTP_ERRORLOG => '/usr/local/apache/logs/error_log',
                    INCOMING => 'ftp://pause.perl.org/incoming/',
                    INCOMING_LOC => '/home/ftp/incoming/',
                    MAXRETRIES => 16,
                    MIRRORCONFIG => '/usr/local/mirror/mymirror.config',
                    MLROOT => '/home/ftp/pub/PAUSE/authors/id/',
                    MOD_DATA_SOURCE_NAME => "dbi:mysql:mod",
                    NO_SUCCESS_BREAK => 900,
                    P5P => 'perl-release-announce@perl.org',
                    PAUSE_LOG => "/home/k/PAUSE/log/paused.log",
                    PAUSE_LOG_DIR => "/home/k/PAUSE/log/",
                    PAUSE_PUBLIC_DATA => '/home/ftp/pub/PAUSE/PAUSE-data',
                    PML => 'ftp://pause.perl.org/pub/PAUSE/authors/id/',
                    SLEEP => 90,
                    # path to repository without "/trunk"
                    SVNPATH => "/home/SVN/repos/pause",
                    # path to where we find the svn binaries
                    SVNBIN => "/home/SVN/local/subversion/bin",
                    TIMEOUT => 60*60,
                    TMP => '/home/ftp/tmp/',
                    UPLOAD => 'upload@pause.perl.org',
     # sign the auto-generated CHECKSUM files with:
     CHECKSUMS_SIGNING_PROGRAM => ('gpg --homedir /home/k/PAUSE/111_sensi'.
                                   'tive/gnupg-pause-batch-signing-home  '.
                                   '--clearsign --default-key '),
     CHECKSUMS_SIGNING_KEY => '450F89EC',
    };


require PrivatePAUSE;


=pod

The following $PAUSE::Config keys are defined in PrivatePAUSE.pm:

              AUTHEN_DATA_SOURCE_USER
              AUTHEN_DATA_SOURCE_PW
              MOD_DATA_SOURCE_USER
              MOD_DATA_SOURCE_PW

These are usernames and passwords in the two mysql databases.

=cut



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

sub urecord {
  my($ruser) = @_;
  return unless $ruser;
  my $db = DBI->connect(
			$PAUSE::Config->{MOD_DATA_SOURCE_NAME},
			$PAUSE::Config->{MOD_DATA_SOURCE_USER},
			$PAUSE::Config->{MOD_DATA_SOURCE_PW},
			{ RaiseError => 1 }
		       )
      or Carp::croak(qq{Can't DBI->connect(): $DBI::errstr});
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
  my $db = DBI->connect(
			$PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME},
			$PAUSE::Config->{AUTHEN_DATA_SOURCE_USER},
			$PAUSE::Config->{AUTHEN_DATA_SOURCE_PW},
		       );
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

1;
