package Test::PAUSE::Web;

use strict;
use warnings;
use FindBin;
use JSON::PP; # just to avoid redefine warnings
use Path::Tiny;
use DBI;
use LWP::ConsoleLogger::Easy qw/debug_ua/;
use Plack::Test;
use HTTP::Message::PSGI;
use WWW::Mechanize;
use Test::More;
use Exporter qw/import/;
use Try::Tiny;
use Test::PAUSE::MySQL;

#our $AppRoot = path(__FILE__)->parent->parent->parent->parent->parent->parent->realpath;
our $AppRoot = path(__FILE__)->parent->parent->parent->parent->parent->parent->parent->realpath;
our $TmpDir = Path::Tiny->tempdir(TEMPLATE => "pause_web_XXXXXXXX");
our $TestRoot = path($TmpDir)->realpath;
our $TestEmail = 'pause_admin@localhost.localdomain';
our $DeadMeatDir = path($AppRoot)->child("tmp/deadmeat");
our @EXPORT = @Test::More::EXPORT;

our $FilenameToUpload = "Hash-RenameKey-0.02.tar.gz";
our $FileToUpload = "$AppRoot/t/staging/$FilenameToUpload";

push @INC, "$AppRoot/lib", "$AppRoot/lib/pause_2017", "$AppRoot/privatelib";

$TmpDir->child($_)->mkpath for qw/rundata incoming etc public log/;
$TmpDir->child('log')->child('paused.log')->touch();

$INC{"PrivatePAUSE.pm"} = 1;
$ENV{EMAIL_SENDER_TRANSPORT} = "Test";

require PAUSE;

$PAUSE::Config->{DOCUMENT_ROOT} = "$AppRoot/htdocs";
$PAUSE::Config->{PID_DIR} = $TestRoot;
$PAUSE::Config->{ADMIN} = $TestEmail;
$PAUSE::Config->{ADMINS} = [$TestEmail];
$PAUSE::Config->{CPAN_TESTERS} = $TestEmail;
$PAUSE::Config->{TO_CPAN_TESTERS} = $TestEmail;
$PAUSE::Config->{REPLY_TO_CPAN_TESTERS} = $TestEmail;
$PAUSE::Config->{GONERS_NOTIFY} = $TestEmail;
$PAUSE::Config->{P5P} = $TestEmail;
$PAUSE::Config->{MLROOT} = "$TestRoot/public/authors/id";
$PAUSE::Config->{ML_CHOWN_USER} = 'ishigaki';
$PAUSE::Config->{ML_CHOWN_GROUP} = 'ishigaki';
$PAUSE::Config->{ML_MIN_INDEX_LINES} = 0;
$PAUSE::Config->{ML_MIN_FILES} = 0;
$PAUSE::Config->{RUNDATA} = "$TestRoot/rundata";
$PAUSE::Config->{UPLOAD} = $TestEmail;
$PAUSE::Config->{HAVE_PERLBAL} = 0;
$PAUSE::Config->{SLEEP} = 1;
$PAUSE::Config->{INCOMING} = "file://$TestRoot/incoming/";
$PAUSE::Config->{PAUSE_LOG} = "$TestRoot/log/paused.log";
$PAUSE::Config->{PAUSE_LOG_DIR} = "$TestRoot/log";

# These will get changed every time you run setup()
$PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME} = "";
$PAUSE::Config->{MOD_DATA_SOURCE_NAME}    = "";

$ENV{TEST_PAUSE_WEB} = 1;

our $AuthDBH;
our $ModDBH;

my $dbh_attr = {ShowErrorStatement => 1};

sub authen_dbh { $AuthDBH ||= authen_db()->dbh }
sub mod_dbh    { $ModDBH ||= mod_db()->dbh }

our $AuthDB;
sub authen_db {
    my $db = $AuthDB ||= Test::PAUSE::MySQL->new(
      schemas => ["$AppRoot/doc/authen_pause.schema.txt"]
    );
    $PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME} = $db->dsn;
    $db;
}

our $ModDB;
sub mod_db {
    my $db = $ModDB ||= Test::PAUSE::MySQL->new(
      schemas => ["$AppRoot/doc/mod.schema.txt"]
    );
    $PAUSE::Config->{MOD_DATA_SOURCE_NAME} = $db->dsn;
    $db;
}

sub setup { # better to use Test::mysqld
  my $class = shift;

  require PAUSE::Crypt;

  # Remove old DB handles and objects
  undef $AuthDBH;
  undef $AuthDB;
  undef $ModDBH;
  undef $ModDB;

  # test fixture
  { # authen_pause.usertable
    $class->authen_dbh->do(qq{TRUNCATE usertable});
    my $sth = $class->authen_dbh->prepare(qq{
      INSERT INTO usertable (user, password, secretemail)
      VALUES (?, ?, ?)
    });
    $sth->execute("TESTUSER", PAUSE::Crypt::hash_password("test"), $TestEmail);
    $sth->execute("TESTADMIN", PAUSE::Crypt::hash_password("test"), $TestEmail);
  }
  { # authen_pause.grouptable
    $class->authen_dbh->do(qq{TRUNCATE grouptable});
    my $sth = $class->authen_dbh->prepare(qq{
      INSERT INTO grouptable (user, ugroup)
      VALUES (?, ?)
    });
    $sth->execute("TESTADMIN", "admin");
  }
  { # mod.users
    $class->mod_dbh->do(qq{TRUNCATE users});
    my $sth = $class->mod_dbh->prepare(qq{
      INSERT INTO users (userid, fullname, email, homepage, isa_list, introduced, changed, changedby)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    });
    $sth->execute("TESTUSER", "test", $TestEmail, "", "", time, time, "TESTADMIN");
    $sth->execute("TESTADMIN", "test", $TestEmail, "", "", time, time, "TESTADMIN");
  }

  return 1;
}

*WWW::Mechanize::simple_request = sub {
  my ($self, $request) = @_;
  $self->run_handlers( "request_send", $request );

  my $uri = $request->uri;
  $uri->scheme('http')    unless defined $uri->scheme;
  $uri->host('localhost') unless defined $uri->host;

  my $env = $self->prepare_request($request)->to_psgi;
  my $response;
  try {
    $response = HTTP::Response->from_psgi( $self->{app}->($env) );
  }
  catch {
    warn ("PSGI error: $_");
    $response = HTTP::Response->new(500);
    $response->content($_);
    $response->content_type('');
  };
  $response->request($request);
  $self->run_handlers( "response_done", $response );
  return $response;
};

sub new {
  my $class = shift;

  my $app = do "$AppRoot/app_2017.psgi";

  my $mech = WWW::Mechanize->new;
  $mech->{app} = $app;
  debug_ua($mech);
  bless {mech => $mech}, $class;
}

sub get_ok {
  my ($self, $url, @args) = @_;

  $_->remove for $DeadMeatDir->children;
  my $res = $self->{mech}->get($url, @args);
  ok $res->is_success, "GET $url";
  unlike $res->content => qr/(?:HASH|ARRAY|SCALAR|CODE)\(/; # most likely stringified reference
  unless (ok !$DeadMeatDir->children, "no deadmeat for $url") {
      diag("Deadmeat: " . $_) for $DeadMeatDir->children
  };
  ok !grep /(?:HASH|ARRAY|SCALAR|CODE)\(/, map {$_->{email}->as_string} $self->deliveries;
  $self->note_deliveries;
  $self;
}

sub user_get_ok {
  my ($self, $url, @args) = @_;

  $self->{mech}->credentials("TESTUSER", "test");
  $self->get_ok($url, @args);
}

sub admin_get_ok {
  my ($self, $url, @args) = @_;

  $self->{mech}->credentials("TESTADMIN", "test");
  $self->get_ok($url, @args);
}

sub post_ok {
  my ($self, $url, @args) = @_;

  $_->remove for $DeadMeatDir->children;
  my $res = $self->{mech}->post($url, @args);
  ok $res->is_success, "POST $url";
  unlike $res->content => qr/(?:HASH|ARRAY|SCALAR|CODE)\(/; # most likely stringified reference
  ok !$DeadMeatDir->children, "no deadmeat for $url";
  ok !grep /(?:HASH|ARRAY|SCALAR|CODE)\(/, map {$_->{email}->as_string} $self->deliveries;
  $self->note_deliveries;
  $self;
}

sub user_post_ok {
  my ($self, $url, @args) = @_;

  $self->{mech}->credentials("TESTUSER", "test");
  $self->post_ok($url, @args);
}

sub admin_post_ok {
  my ($self, $url, @args) = @_;

  $self->{mech}->credentials("TESTADMIN", "test");
  $self->post_ok($url, @args);
}

sub content {
  my $self = shift;
  $self->{mech}->content;
}

sub file_to_upload {
  wantarray ? ($FileToUpload, $FilenameToUpload) : $FileToUpload;
}

sub copy_to_authors_dir {
  my ($self, $user, $file) = @_;
  my $userhome = PAUSE::user2dir($user);
  my $destination = path("$PAUSE::Config->{MLROOT}/$userhome");
  $destination->mkpath;
  note "copy $file to $destination";
  path($file)->copy($destination);
}

sub deliveries { Email::Sender::Simple->default_transport->deliveries }
sub note_deliveries { note "-- email begin --\n".$_->{email}->as_string."\n-- email end --\n\n" for shift->deliveries }

END { $TmpDir->remove_tree if $TmpDir }

1;
