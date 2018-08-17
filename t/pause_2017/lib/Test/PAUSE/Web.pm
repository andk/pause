package Test::PAUSE::Web;

use strict;
use warnings;
use FindBin;
use JSON::PP; # just to avoid redefine warnings
use Path::Tiny;
use DBI;
use Plack::Test;
use Test::WWW::Mechanize::PSGI;
use Test::More;
use Exporter qw/import/;
use Test::PAUSE::MySQL;
use Email::Sender::Simple;
use Mojo::DOM;

our $AppRoot = path(__FILE__)->parent->parent->parent->parent->parent->parent->realpath;
#our $AppRoot = path(__FILE__)->parent->parent->parent->parent->parent->parent->parent->realpath;
our $TmpDir = Path::Tiny->tempdir(TEMPLATE => "pause_web_XXXXXXXX");
our $TestRoot = path($TmpDir)->realpath;
our $TestEmail = 'pause_admin@localhost.localdomain';
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
$PAUSE::Config->{INCOMING_LOC} = "$TestRoot/incoming/";
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
    for my $user ("TESTUSER", "TESTADMIN") {
      $class->authen_db->insert('usertable', {
        user => $user,
        password => PAUSE::Crypt::hash_password("test"),
        secretemail => $TestEmail,
      });
      my $user_dir = join "/", $PAUSE::Config->{MLROOT}, PAUSE::user2dir($user);
      path($user_dir)->mkpath;
    }
  }
  { # authen_pause.grouptable
    $class->authen_dbh->do(qq{TRUNCATE grouptable});
    $class->authen_db->insert('grouptable', {user => "TESTADMIN", ugroup => "admin"});
  }
  { # mod.users
    $class->mod_dbh->do(qq{TRUNCATE users});
    for my $user ("TESTUSER", "TESTADMIN") {
      $class->mod_db->insert('users', {userid => $user, email => $TestEmail});
    }
  }

  return 1;
}

sub new {
  my ($class, %args) = @_;

  my $psgi = $ENV{TEST_PAUSE_WEB_PSGI} // "app_2017.psgi";
  my $app = do "$AppRoot/$psgi";

  $args{mech} = Test::WWW::Mechanize::PSGI->new(app => $app, cookie_jar => {});
  if (!$INC{'Devel/Cover.pm'} and !$ENV{TRAVIS} and eval {require LWP::ConsoleLogger::Easy; 1}) {
    LWP::ConsoleLogger::Easy::debug_ua($args{mech});
  }
  $args{pass} ||= "test" if $args{user};

  $class->clear_deliveries;

  bless \%args, $class;
}

sub set_credentials {
  my $self = shift;
  note "log in as ".$self->{user};
  $self->{mech}->credentials($self->{user}, $self->{pass});
}

sub get_ok {
  my ($self, $url, @args) = @_;

  $self->set_credentials if $self->{user};
  my $res = $self->{mech}->get($url, @args);
  ok $res->is_success, "GET $url";
  unlike $res->content => qr/(?:HASH|ARRAY|SCALAR|CODE)\(/; # most likely stringified reference
  ok !grep /(?:HASH|ARRAY|SCALAR|CODE)\(/, map {$_->{email}->as_string} $self->deliveries;
  $self->note_deliveries;
  $self;
}

sub post_ok {
  my ($self, $url, @args) = @_;

  my $res = $self->{mech}->post($url, @args);
  ok $res->is_success, "POST $url";
  unlike $res->content => qr/(?:HASH|ARRAY|SCALAR|CODE)\(/; # most likely stringified reference
  ok !grep /(?:HASH|ARRAY|SCALAR|CODE)\(/, map {$_->{email}->as_string} $self->deliveries;
  $self->note_deliveries;
  $self;
}

sub safe_post_ok {
  my ($self, $url, @args) = @_;

  my $res = $self->{mech}->get($url);
  ok $res->is_success, "GET $url";
  my $token = Mojo::DOM->new($res->content)->at('input[name="csrf_token"]')->attr('value');
  $args[0]->{csrf_token} = $token if @args and ref $args[0] eq 'HASH';

  $res = $self->{mech}->post($url, @args);
  ok $res->is_success, "POST $url";
  unlike $res->content => qr/(?:HASH|ARRAY|SCALAR|CODE)\(/; # most likely stringified reference
  ok !grep /(?:HASH|ARRAY|SCALAR|CODE)\(/, map {$_->{email}->as_string} $self->deliveries;
  $self->note_deliveries;
  $self;
}

sub tests_for {
  my ($self, $permission) = @_;
  my @tests;
  if ($permission eq "public") {
    push @tests, (
      ["/pause/query"],
      ["/pause/query", "TESTUSER"],
      ["/pause/query", "TESTADMIN"],
    );
  }
  if ($permission ne "admin") {
    push @tests, ["/pause/authenquery", "TESTUSER"];
  }
  push @tests, ["/pause/authenquery", "TESTADMIN"];
  $ENV{PAUSE_WEB_TEST_ALL} && wantarray ? @tests : $tests[0];
}

sub content {
  my $self = shift;
  $self->{mech}->content;
}

sub dom {
  my $self = shift;
  Mojo::DOM->new($self->content);
}

sub text_is {
  my ($self, $selector, $expects) = @_;
  my $at = $self->dom->at($selector);
  if ($at) {
    my $text = $at->all_text // '';
    is $text => $expects;
  } else {
    fail "'$selector' is not found";
  }
  $self;
}

sub text_like {
  my ($self, $selector, $expects) = @_;
  my $at = $self->dom->at($selector);
  if ($at) {
    my $text = $at->all_text // '';
    like $text => $expects;
  } else {
    fail "'$selector' is not found";
  }
  $self;
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
sub clear_deliveries { Email::Sender::Simple->default_transport->clear_deliveries }
sub note_deliveries { note "-- email begin --\n".$_->{email}->as_string."\n-- email end --\n\n" for shift->deliveries }

END { $TmpDir->remove_tree if $TmpDir }

1;
