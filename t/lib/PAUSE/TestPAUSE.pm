package PAUSE::TestPAUSE;
use Moose;
use MooseX::StrictConstructor;

use v5.36.0;
use autodie;

use DBI;
use DBIx::RunSQL;
use Email::Sender::Transport::Test;
use File::Copy::Recursive qw(fcopy dircopy);
use File::Path qw(make_path);
use File::pushd;
use File::Temp ();
use File::Which;
use Path::Class;
use Process::Status;

# This one, we don't expect to be used.  In a weird world, we'd mark it fatal
# or something so we could say "nothing should log outside of test code."
# -- rjbs, 2019-04-27
use PAUSE::Logger '$Logger' => { init => {
  ident     => 'TestPAUSE',
  facility  => undef,
  to_self   => 0,
  to_stderr => 1,
} };

use PAUSE;
use PAUSE::mldistwatch;
use PAUSE::TestPAUSE::Result;

use namespace::autoclean;

sub init_new {
  my ($class, @arg) = @_;
  my $self = $class->new(@arg);

  my $authors_dir = $self->tmpdir->subdir(qw(cpan authors id));
  make_path $authors_dir->stringify;

  my $modules_dir = $self->tmpdir->subdir(qw(cpan modules));
  make_path $modules_dir->stringify;
  my $index_06 = $modules_dir->file(qw(06perms.txt.gz));

  {
    File::Copy::copy('corpus/empty.txt.gz', $index_06->stringify)
      or die "couldn't set up bogus 06perms: $!";
  }
  return $self;
}

has logger => (
  is    => 'ro',
  lazy  => 1,
  default => sub {
    PAUSE::Logger->default_logger_class->new({
      ident     => 'TestPAUSE',
      facility  => undef,
      to_self   => 1,
      to_stderr => $ENV{TEST_VERBOSE} ? 1 : 0,

      to_file   => 1,
      log_path  => $_[0]->tmpdir,
      log_file  => "pause.log",
    });
  }
);

has _tmpdir_obj => (
  is       => 'ro',
  isa      => 'Defined',
  lazy     => 1,
  init_arg => undef,
  default  => sub { File::Temp->newdir; },
);

has tmpdir => (
  is      => 'ro',
  lazy    => 1,
  default => sub { dir($_[0]->_tmpdir_obj) },
);

has email_sender_transport => (
  is      => 'rw',
  isa     => 'Str',
  default => sub { $ENV{EMAIL_SENDER_TRANSPORT} // 'Test' },
);

has email_sender_transport_args => (
  is      => 'ro',
  isa     => 'HashRef[Str]',
  predicate => 'has_email_sender_transport_args',
);

sub deploy_schemas_at {
  my ($self, $dir) = @_;

  my %schemas = (
    authen => "doc/schemas/authen_pause.schema.sqlite",
    mod => "doc/schemas/mod.schema.sqlite",
  );

  while ( my ($db,$sql) = each %schemas ) {
    DBIx::RunSQL->create(
      dsn => "dbi:SQLite:dbname=$dir/$db.sqlite",
      sql => $sql,
    );
  }
}

has db_root => (
  is   => 'ro',
  lazy => 1,
  init_arg => undef,
  builder => '_build_db_root',
);

sub _build_db_root {
  my ($self) = @_;

  my $tmpdir = $self->tmpdir;
  my $db_root = File::Spec->catdir($tmpdir, 'db');
  mkdir $db_root;

  $self->deploy_schemas_at($db_root);

  return $db_root;
}

sub add_first_come {
  my ($self, $userid, $package) = @_;

  my $dir = $self->db_root;
  my $dbh = DBI->connect(
    "dbi:SQLite:dbname=$dir/mod.sqlite",
    undef,
    undef,
    { RaiseError => 1 },
  );

  $dbh->do(
    q{
      INSERT INTO primeur (userid, package, lc_package) VALUES (?, ?, ?);
      INSERT INTO perms   (userid, package, lc_package) VALUES (?, ?, ?);
    },
    undef,
    (uc $userid, $package, lc $package) x 2,
  );
}

sub add_comaint {
  my ($self, $userid, $package) = @_;

  my $dir = $self->db_root;
  my $dbh = DBI->connect(
    "dbi:SQLite:dbname=$dir/mod.sqlite",
    undef,
    undef,
    { RaiseError => 1 },
  );

  $dbh->do(
    q{
      INSERT INTO perms (userid, package, lc_package) VALUES (?, ?, ?);
    },
    undef,
    uc $userid,
    $package,
    lc $package,
  );
}

sub import_author_root {
  my ($self, $author_root) = @_;

  my $cpan_root = File::Spec->catdir($self->tmpdir, 'cpan');
  my $ml_root = File::Spec->catdir($cpan_root, qw(authors id));
  dircopy($author_root, $ml_root);
}

sub upload_author_fake {
  my ($self, $author, $fake, $extra) = @_;

  require Module::Faker; # We require 0.020 -- rjbs, 2019-04-25

  if (ref $fake) {
    $fake->{cpan_author} //= $author;
    Carp::croak("use more_meta, not 3rd parameter, for faker here") if $extra;
  } else {
    my $ext = "tar.gz";
    if ($fake =~ s/\.(tar\.gz|zip)\z//) {
      $ext = $1;
    }

    my ($name, $version) = $fake =~ /\A (.+) - ([^-]+) \z/x;

    Carp::croak("bogus fake dist name: $fake")
      unless defined $name and defined $version;

    $fake = {
      cpan_author => $author,
      name        => $name,
      version     => $version,
      archive_ext => $ext,
      ($extra ? %$extra : ()),
    };
  }

  my $dist = Module::Faker::Dist->from_struct($fake);

  my $cpan_root   = File::Spec->catdir($self->tmpdir, 'cpan');
  my $author_root = File::Spec->catdir($cpan_root, qw(authors id));

  return $dist->make_archive({
    dir           => $author_root,
    author_prefix => 1,
  });
}

sub upload_author_file {
  my ($self, $author, $file) = @_;

  $author = uc $author;
  my $cpan_root  = File::Spec->catdir($self->tmpdir, 'cpan');
  my $author_dir = File::Spec->catdir(
    $cpan_root,
    qw(authors id),
    (substr $author, 0, 1),
    (substr $author, 0, 2),
    $author,
  );

  make_path( $author_dir );
  fcopy($file, $author_dir);

  return File::Spec->catfile($author_dir, $file);
}

sub upload_author_garbage {
  my ($self, $author, $file) = @_;

  $author = uc $author;
  my $cpan_root  = File::Spec->catdir($self->tmpdir, 'cpan');
  my $author_dir = File::Spec->catdir(
    $cpan_root,
    qw(authors id),
    (substr $author, 0, 1),
    (substr $author, 0, 2),
    $author,
  );

  make_path( $author_dir );
  my $target = File::Spec->catfile($author_dir, $file);
  system('dd', 'if=/dev/random', "of=$target", "count=20", "status=none"); # write 20k

  Process::Status->assert_ok("dd from /dev/random to $target");

  return $target;
}

has pause_config_overrides => (
  is  => 'ro',
  isa => 'HashRef',
  lazy => 1,
  init_arg => undef,
  builder  => '_build_pause_config_overrides',
);

my $GIT_CONFIG = <<'END_GIT_CONFIG';
[user]
  email = pause.git@example.com
  name  = "PAUSE Daemon Git User"
END_GIT_CONFIG

sub _build_pause_config_overrides {
  my ($self) = @_;

  my $tmpdir = $self->tmpdir;

  my $cpan_root = File::Spec->catdir($tmpdir, 'cpan');
  my $ml_root = File::Spec->catdir($cpan_root, qw(authors id));

  make_path( File::Spec->catdir($cpan_root, 'modules') );

  my $db_root = $self->db_root;

  my $pid_dir = File::Spec->catdir($tmpdir, 'run');
  mkdir $pid_dir;

  my $git_dir = File::Spec->catdir($tmpdir, 'git');
  mkdir $git_dir;

  {
    my $chdir_guard = pushd($git_dir);
    system(qw(git init --quiet --initial-branch master)) and die "error running git init";

    my $git_config = File::Spec->catdir($git_dir, '.git/config');
    open my $config_fh, '>', $git_config
      or die "can't create git config at $git_config: $!";

    print {$config_fh} $GIT_CONFIG;
    close $config_fh
      or die "can't write git config at $git_config: $!";
  }

  my $dsnbase = "DBI:SQLite:dbname=$db_root";

  my $overrides = {
    AUTHEN_DATA_SOURCE_NAME   => "$dsnbase/authen.sqlite",
    CHECKSUMS_SIGNING_PROGRAM => "\0",
    GITROOT                   => $git_dir,
    GZIP_OPTIONS              => '',
    MLROOT                    => File::Spec->catdir($ml_root),
    ML_CHOWN_GROUP     => +(getgrgid($)))[0],
    ML_CHOWN_USER      => +(getpwuid($>))[0],
    ML_MIN_FILES       => 0,
    ML_MIN_INDEX_LINES => 0,
    MOD_DATA_SOURCE_NAME => "$dsnbase/mod.sqlite",
    PID_DIR              => $pid_dir,
  };

  return $overrides;
}

sub with_our_config {
  my ($self, $code) = @_;

  local $PAUSE::USE_RECENTFILE_HOOKS = 0;
  local $PAUSE::Config = {
    %{ $PAUSE::Config },
    %{ $self->pause_config_overrides },
  };

  local $Logger = $self->logger;

  $code->($self);
}

sub test_reindex {
  my ($self, $arg) = @_;
  $arg //= {};

  $self->with_our_config(sub {
    my $self = shift;
    my $chdir_guard = pushd;

    Email::Sender::Simple->reset_default_transport;

    # If we aren't using the Test transport, we need to wrap the chosen
    # transport with Email::Sender::Transport::KeepDeliveries as test_reindex
    # expects to be able to access ->deliveries() for all sent email.
    my $transport = $self->email_sender_transport;
    my $wrap_transport = $transport ne 'Test';

    local $ENV{EMAIL_SENDER_TRANSPORT} =
      $wrap_transport ? 'KeepDeliveries' : $transport;

    local $ENV{EMAIL_SENDER_TRANSPORT_transport_class} = $transport
      if $wrap_transport;

    my %args = $self->has_email_sender_transport_args
             ? %{ $self->email_sender_transport_args }
             : ();

    %args = map {;
      "EMAIL_SENDER_TRANSPORT_transport_arg_$_" => $args{$_}
    } keys %args;

    local @ENV{keys %args} = values %args;

    my @stray_mail = Email::Sender::Simple->default_transport->deliveries;

    die "stray mail in test mail trap before reindex" if @stray_mail;

    my $existing_log_events = $self->logger->events->@*;

    if ($arg->{pick}) {
      my $dbh = PAUSE::dbh();
      $dbh->do("DELETE FROM distmtimes WHERE dist = ?", undef, $_)
        for @{ $arg->{pick} };
    }

    my sub filestate ($file) {
      return ';;' unless -e $file;
      my @stat = stat $file;
      return join q{;}, @stat[0,1,7]; # dev, ino, size
    }

    my $package_file = $self->tmpdir->file(qw(cpan modules 02packages.details.txt.gz));

    my $old_package_state = filestate($package_file);

    PAUSE::mldistwatch->new({
      sleep => 0,
      ($arg->{pick} ? (pick => $arg->{pick}) : ()),
    })->reindex;

    $arg->{after}->($self->tmpdir) if $arg->{after};

    # The first $existing_log_events were already there.  We only care about
    # once added during the indexer run.
    my @log_events = $self->logger->events->@*;
    splice @log_events, 0, $existing_log_events;

    my @deliveries = Email::Sender::Simple->default_transport->deliveries;

    Email::Sender::Simple->default_transport->clear_deliveries;

    my $new_package_state = filestate($package_file);

    return PAUSE::TestPAUSE::Result->new({
      tmpdir => $self->tmpdir,
      config_overrides => $self->pause_config_overrides,
      authen_db_file   => File::Spec->catfile($self->db_root, 'authen.sqlite'),
      mod_db_file      => File::Spec->catfile($self->db_root, 'mod.sqlite'),
      deliveries       => \@deliveries,
      log_events       => \@log_events,
      updated_02packages => $old_package_state ne $new_package_state,
    });
  });
}

sub run_shell {
  my ($self) = @_;

  my $chdir_guard = pushd($self->tmpdir);

  $self->logger->log_fatal([ "\$ENV{SHELL} %s is not runnable", $ENV{SHELL} ])
    unless $ENV{SHELL} && -x $ENV{SHELL};

  $self->logger->log("running a shell ($ENV{SHELL})");
  system($ENV{SHELL});
  Process::Status->assert_ok($ENV{SHELL});
}

1;
