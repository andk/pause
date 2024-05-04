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
use URI;
use URI::QueryParam;

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
require PAUSE::Web::Config;

$PAUSE::Config->{DOCUMENT_ROOT} = "$AppRoot/htdocs";
$PAUSE::Config->{PID_DIR} = $TestRoot;
$PAUSE::Config->{INTERNAL_REPORT_ADDRESS} = $TestEmail;
$PAUSE::Config->{CONTACT_ADDRESS} = $TestEmail;
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
$PAUSE::Config->{NOREPLY_ADDRESS} = $TestEmail;
$PAUSE::Config->{RUNDATA} = "$TestRoot/rundata";
$PAUSE::Config->{HAVE_PERLBAL} = 0;
$PAUSE::Config->{SLEEP} = 1;
$PAUSE::Config->{INCOMING} = "file://$TestRoot/incoming/";
$PAUSE::Config->{INCOMING_LOC} = "$TestRoot/incoming/";
$PAUSE::Config->{PAUSE_LOG} = "$TestRoot/log/paused.log";
$PAUSE::Config->{PAUSE_LOG_DIR} = "$TestRoot/log";
$PAUSE::Config->{RECAPTCHA_ENABLED} = 0;

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

  $class->reset_fixture;
}

sub reset_fixture {
  my $self = shift;

  # test fixture
  { # authen_pause.usertable
    $self->authen_dbh->do(qq{TRUNCATE usertable});
    for my $user ("TESTUSER", "TESTUSER2", "TESTUSER3", "TESTUSER4", "TESTADMIN", "TESTCNSRD") {
      $self->authen_db->insert('usertable', {
        user => $user,
        password => PAUSE::Crypt::hash_password("test"),
        secretemail => lc($user) . '@localhost',
      });
      my $user_dir = join "/", $PAUSE::Config->{MLROOT}, PAUSE::user2dir($user);
      path($user_dir)->mkpath;
    }
  }
  { # authen_pause.grouptable
    $self->authen_dbh->do(qq{TRUNCATE grouptable});
    $self->authen_db->insert('grouptable', {user => "TESTADMIN", ugroup => "admin"});
  }
  { # mod.users
    $self->mod_dbh->do(qq{TRUNCATE users});
    for my $user ("TESTUSER", "TESTUSER2", "TESTUSER3", "TESTUSER4", "TESTADMIN", "TESTCNSRD") {
      $self->mod_db->insert('users', {
        userid => $user,
        fullname => "$user Name",
        email => ($user eq "TESTCNSRD" ? "CENSORED" : (lc($user) . '@localhost')),
        cpan_mail_alias => 'secr',
        isa_list => '',
      });
    }
  }
  $self;
}

sub new {
  my ($class, %args) = @_;

  my $psgi = $ENV{TEST_PAUSE_WEB_PSGI} // "app_2017.psgi";
  my $app = do "$AppRoot/$psgi";

  $args{mech} = Test::WWW::Mechanize::PSGI->new(app => $app, cookie_jar => {});
  if (!$INC{'Devel/Cover.pm'} and !$ENV{TRAVIS} and $ENV{HARNESS_VERBOSE} and eval {require LWP::ConsoleLogger::Easy; 1}) {
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

sub get {
  my ($self, $url, @args) = @_;

  $self->set_credentials if $self->{user};
  if (@args and ref $args[0] eq 'HASH') {
    my $params = shift @args;
    $url = URI->new($url);
    $url->query_param($_ => $params->{$_}) for keys %$params;
  }
  my $res = $self->{mech}->get($url, @args);
  unlike $res->decoded_content => qr/(?:HASH|ARRAY|SCALAR|CODE)\(/; # most likely stringified reference
  ok !grep /(?:HASH|ARRAY|SCALAR|CODE)\(/, map {$_->as_string} $self->deliveries;
  $res;
}

sub get_ok {
  my ($self, $url, @args) = @_;

  $self->clear_deliveries;
  my $res = $self->get($url, @args);
  ok $res->is_success, "GET $url";
  $self->title_is_ok($url);
  $self->note_deliveries;
  $self;
}

sub post {
  my ($self, $url, @args) = @_;

  $self->set_credentials if $self->{user};
  my $res = $self->{mech}->post($url, @args);
  unlike $res->decoded_content => qr/(?:HASH|ARRAY|SCALAR|CODE)\(/; # most likely stringified reference
  ok !grep /(?:HASH|ARRAY|SCALAR|CODE)\(/, map {$_->as_string} $self->deliveries;
  $res;
}

sub post_ok {
  my ($self, $url, @args) = @_;

  $self->clear_deliveries;
  my $res = $self->post($url, @args);
  ok $res->is_success, "POST $url";
  $self->title_is_ok($url);
  $self->note_deliveries;
  $self;
}

sub post_with_token {
  my ($self, $url, @args) = @_;

  my $res = $self->get($url);
  return $res unless $res->is_success;
  my $input = Mojo::DOM->new($res->decoded_content)->at('input[name="csrf_token"]');
  my $token = $input ? $input->attr('value') : '';
  ok $token, "Got a CSRF token";
  @args = {} if !@args;
  $args[0]->{csrf_token} = $token if @args and ref $args[0] eq 'HASH';

  $res = $self->post($url, @args);
}

sub post_with_token_ok {
  my ($self, $url, @args) = @_;

  $self->clear_deliveries;
  my $res = $self->post_with_token($url, @args);
  ok $res->is_success, "POST $url";
  $self->title_is_ok($url);
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
    is $text => $expects, "$selector is $expects";
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
    like $text => $expects, "$selector like $expects";
  } else {
    fail "'$selector' is not found";
  }
  $self;
}

sub text_unlike {
  my ($self, $selector, $expects) = @_;
  my $at = $self->dom->at($selector);
  if ($at) {
    my $text = $at->all_text // '';
    unlike $text => $expects, "$selector unlike $expects";
  } else {
    fail "'$selector' is not found";
  }
  $self;
}

sub title_is_ok {
  my ($self, $url) = @_;
  return if $self->dom->at('p.error_message'); # ignore if error
  return if $self->{mech}->content_type !~ /html/i;

  my ($action) = $url =~ /ACTION=(\w+)/;
  $action ||= $url; # in case action is passed as url
  return if $action =~ /^select_(user|ml_action)$/;
  my $conf = PAUSE::Web::Config->action($action);
  return if $conf->{has_title}; # uses different title from its data source

  my $title = $conf->{verb};
  return unless $title; # maybe top page

  $self->text_is("h2.firstheader", $title);
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

sub save_to_authors_dir {
  my ($self, $user, $file, $body) = @_;
  my $userhome = PAUSE::user2dir($user);
  my $destination = path("$PAUSE::Config->{MLROOT}/$userhome");
  $destination->mkpath;
  note "save $file to $destination";
  path("$destination/$file")->spew($body);
}

sub remove_authors_dir {
  my ($self, $user) = @_;
  my $userhome = PAUSE::user2dir($user);
  my $destination = path("$PAUSE::Config->{MLROOT}/$userhome");
  $destination->remove_tree;
}

sub deliveries { map { $_->{email}->cast('Email::MIME') } Email::Sender::Simple->default_transport->deliveries }
sub clear_deliveries { Email::Sender::Simple->default_transport->clear_deliveries }
sub note_deliveries { note "-- email begin --\n".$_->as_string."\n-- email end --\n\n" for shift->deliveries }

END { $TmpDir->remove_tree if $TmpDir }

sub reset_module_fixture {
    my $self = shift;

    $self->mod_dbh->do("TRUNCATE primeur");
    $self->mod_dbh->do("TRUNCATE perms");
    $self->mod_dbh->do("TRUNCATE packages");

    my @dists = (
        {
            name => 'Module-Admin',
            owner => 'TESTADMIN',
            packages => [qw/
                Module::Admin::Foo
                Module::Admin::Bar
            /],
            comaints => [qw/TESTUSER2/],
        },
        {
            name => 'Module-User',
            owner => 'TESTUSER',
            packages => [qw/
                Module::User::Foo
                Module::User::Bar
            /],
            comaints => [
                [TESTADMIN => [qw/Module::User::Foo/]],
                [TESTUSER2 => [qw/Module::User::Bar/]],
            ],
        },
        {
            name => 'Module-User-Foo-Baz',
            owner => 'TESTUSER',
            packages => [qw/
                Module::User::Foo::Baz
            /],
        },
        {
            name => 'Module-Comaint',
            owner => 'TESTUSER2',
            packages => [qw/
                Module::Comaint
                Module::Comaint::Foo
            /],
            comaints => [qw/TESTADMIN TESTUSER/],
        },
        {
            name => 'Module-Managed',
            owner => 'TESTUSER2',
            packages => [qw/
                Module::Managed
                Module::Managed::Foo
            /],
            comaints => [
                [TESTUSER3 => [qw/Module::Managed/]],
            ],
        },
        {
            name => 'Module-Unrelated',
            owner => 'TESTUSER3',
            packages => [qw/
                Module::Unrelated
                Module::Unrelated::Foo
            /],
        },
    );

    for my $dist (@dists) {
        for my $package (@{$dist->{packages}}) {
            my $userdir = _userdir($dist->{owner});
            $self->mod_db->insert("packages", {
                package => $package,
                version => '0.01',
                dist => "$userdir/$dist->{name}-0.01.tar.gz",
                distname => $dist->{name},
                filemtime => time,
                pause_reg => time,
                status => 'index',
            });
            $self->mod_db->insert("primeur", {
                package => $package,
                userid => $dist->{owner},
            });
        }
        for my $comaint (@{$dist->{comaints} // []}) {
            if (ref $comaint eq 'ARRAY') {
                my ($id, $packages) = @$comaint;
                for my $package (@$packages) {
                    $self->mod_db->insert("perms", {
                        package => $package,
                        userid => $id,
                    });
                }
            } else {
                for my $package (@{$dist->{packages}}) {
                    $self->mod_db->insert("perms", {
                        package => $package,
                        userid => $comaint,
                    });
                }
            }
        }
    }
}

sub _userdir {
    my $user = shift;
    join '/', substr($user, 0, 1), substr($user, 0, 2), $user;
}

1;
