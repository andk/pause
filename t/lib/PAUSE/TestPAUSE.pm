package PAUSE::TestPAUSE;
use Moose;
use MooseX::StrictConstructor;

use autodie;

use DBI;
use DBIx::RunSQL;
use File::Copy::Recursive qw(dircopy);
use File::Path qw(make_path);
use File::pushd;
use File::Temp ();
use File::Which;
use Path::Class;

use PAUSE;
use PAUSE::mldistwatch;
use PAUSE::TestPAUSE::Result;

use namespace::autoclean;

has _tmpdir_obj => (
  is       => 'ro',
  isa      => 'Defined',
  init_arg => undef,
  default  => sub { File::Temp->newdir; },
);

sub tmpdir {
  my ($self) = @_;
  return dir($self->_tmpdir_obj);
}

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

    ($ENV{TEST_VERBOSE} ? () : (LOG_CALLBACK => sub { })),
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

    PAUSE::mldistwatch->new({ sleep => 0 })->reindex;

    $code->($self->tmpdir) if $code;

    return PAUSE::TestPAUSE::Result->new({
      tmpdir => $self->tmpdir,
      config_overrides => $self->pause_config_overrides,
      authen_db_file   => File::Spec->catfile($self->db_root, 'authen.sqlite'),
      mod_db_file      => File::Spec->catfile($self->db_root, 'mod.sqlite'),
    });
  });
}

1;
