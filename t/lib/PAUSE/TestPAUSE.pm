package PAUSE::TestPAUSE;
use Moose;
use MooseX::StrictConstructor;

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
  default => 'Test',
);

has email_sender_transport_args => (
  is      => 'ro',
  isa     => 'HashRef[Str]',
  default => sub { {} },
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

sub import_author_root {
  my ($self, $author_root) = @_;

  my $cpan_root = File::Spec->catdir($self->tmpdir, 'cpan');
  my $ml_root = File::Spec->catdir($cpan_root, qw(authors id));
  dircopy($author_root, $ml_root);
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
}

has pause_config_overrides => (
  is  => 'ro',
  isa => 'HashRef',
  lazy => 1,
  init_arg => undef,
  builder  => '_build_pause_config_overrides',
);

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
    system(qw(git init)) and die "error running git init";
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

    LOG_CALLBACK       => $ENV{TEST_VERBOSE}
                        ? sub { my (undef, undef, @what) = @_;
                                push @what, "\n" unless $what[-1] =~ m{\n$};
                                print STDERR @what;  }
                        : sub { },
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

  $code->($self);
}

sub test_reindex {
  my ($self, $code) = @_;

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

    my %args = %{ $self->email_sender_transport_args };

    %args = map {;
      "EMAIL_SENDER_TRANSPORT_transport_arg_$_" => $args{$_}
    } keys %args;

    local @ENV{keys %args} = values %args;

    my @stray_mail = Email::Sender::Simple->default_transport->deliveries;

    die "stray mail in test mail trap before reindex" if @stray_mail;

    PAUSE::mldistwatch->new({ sleep => 0 })->reindex;

    $code->($self->tmpdir) if $code;

    my @deliveries = Email::Sender::Simple->default_transport->deliveries;

    Email::Sender::Simple->default_transport->clear_deliveries;

    return PAUSE::TestPAUSE::Result->new({
      tmpdir => $self->tmpdir,
      config_overrides => $self->pause_config_overrides,
      authen_db_file   => File::Spec->catfile($self->db_root, 'authen.sqlite'),
      mod_db_file      => File::Spec->catfile($self->db_root, 'mod.sqlite'),
      deliveries       => \@deliveries,
    });
  });
}

has _file_index => (
  is      => 'ro',
  default => sub {  {}  },
);

sub file_updated_ok {
  my ($self, $filename, $desc) = @_;
  $desc = defined $desc ? "$desc: " : q{};

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  unless (-e $filename) {
    return Test::More::fail("$desc$filename not updated");
  }

  my ($dev, $ino) = stat $filename;

  my $old = $self->_file_index->{ $filename };

  unless (defined $old) {
    $self->_file_index->{$filename} = "$dev,$ino";
    return Test::More::pass("$desc$filename updated (created)");
  }

  my $ok = Test::More::ok(
    $old ne "$dev,$ino",
    "$desc$filename updated",
  );

  $self->_file_index->{$filename} = "$dev,$ino";
  return $ok;
}

sub file_not_updated_ok {
  my ($self, $filename, $desc) = @_;
  $desc = defined $desc ? "$desc: " : q{};

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $old = $self->_file_index->{ $filename };

  unless (-e $filename) {
    return Test::More::fail("$desc$filename deleted") if $old;
    return Test::More::pass("$desc$filename not created (thus not updated)");
  }

  my ($dev, $ino) = stat $filename;

  unless (defined $old) {
    $self->_file_index->{$filename} = "$dev,$ino";
    return Test::More::fail("$desc$filename updated (created)");
  }

  my $ok = Test::More::ok(
    $old eq "$dev,$ino",
    "$desc$filename not updated",
  );

  return $ok;
}

1;
