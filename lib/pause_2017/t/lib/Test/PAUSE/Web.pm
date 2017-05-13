package Test::PAUSE::Web;

use strict;
use warnings;
use FindBin;
use JSON::PP; # just to avoid redefine warnings
use Path::Tiny;
use DBI;
use PAUSE::Crypt;
use Test::WWW::Mechanize::PSGI;
use Test::More;
use Exporter qw/import/;

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

$TmpDir->child($_)->mkpath for qw/rundata incoming etc public/;

$INC{"PrivatePAUSE.pm"} = 1;

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

$PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME} = "dbi:mysql:test_authen_pause";
$PAUSE::Config->{MOD_DATA_SOURCE_NAME}    = "dbi:mysql:test_mod";

$ENV{TEST_PAUSE_WEB} = 1;

our $AuthDBH;
our $ModDBH;
my $dbh_attr = {ShowErrorStatement => 1};

sub authen_dbh { $AuthDBH ||= DBI->connect(@$PAUSE::Config{qw/AUTHEN_DATA_SOURCE_NAME AUTHEN_DATA_SOURCE_USER AUTHEN_DATA_SOURCE_PW/}, $dbh_attr); }
sub mod_dbh    { $ModDBH ||= DBI->connect(@$PAUSE::Config{qw/MOD_DATA_SOURCE_NAME MOD_DATA_SOURCE_USER MOD_DATA_SOURCE_PW/}, $dbh_attr); }

sub setup { # better to use Test::mysqld
  my $class = shift;

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

sub new {
  my $class = shift;

  my $app = do "$AppRoot/app_2017.psgi";

  bless {mech => Test::WWW::Mechanize::PSGI->new(app => $app)}, $class;
}

sub get_ok {
  my ($self, $url, $args) = @_;

  $_->remove for $DeadMeatDir->children;
  $self->{mech}->get_ok($url, $args, "GET $url");
  ok !$DeadMeatDir->children, "no deadmeat for $url";
  $self;
}

sub user_get_ok {
  my ($self, $url, $args) = @_;

  $self->{mech}->credentials("TESTUSER", "test");
  $self->get_ok($url, $args);
}

sub admin_get_ok {
  my ($self, $url, $args) = @_;

  $self->{mech}->credentials("TESTADMIN", "test");
  $self->get_ok($url, $args);
}

sub post_ok {
  my ($self, $url, $args) = @_;
  $args->{Content} //= {};

  $_->remove for $DeadMeatDir->children;
  $self->{mech}->post_ok($url, $args, "POST $url");
  ok !$DeadMeatDir->children, "no deadmeat for $url";
  $self;
}

sub user_post_ok {
  my ($self, $url, $args) = @_;

  $self->{mech}->credentials("TESTUSER", "test");
  $self->post_ok($url, $args);
}

sub admin_post_ok {
  my ($self, $url, $args) = @_;

  $self->{mech}->credentials("TESTADMIN", "test");
  $self->post_ok($url, $args);
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

END { $TmpDir->remove_tree if $TmpDir }

1;
