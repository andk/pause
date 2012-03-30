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

has author_root => (
  is  => 'ro',
  isa => 'Str',
  required => 1,
);

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

sub test_reindex {
  my ($self, $code) = @_;

  my $tmpdir = $self->tmpdir;

  my $cpan_root = File::Spec->catdir($tmpdir, 'cpan');
  my $ml_root = File::Spec->catdir($cpan_root, qw(authors id));

  make_path( File::Spec->catdir($cpan_root, 'modules') );

  dircopy($self->author_root, $ml_root);

  mkdir File::Spec->catdir($tmpdir, 'db');
  my $db_root = File::Spec->catdir($tmpdir, 'db');

  my $pid_dir = File::Spec->catdir($tmpdir, 'run');
  mkdir $pid_dir;

  my $git_dir = File::Spec->catdir($tmpdir, 'git');
  mkdir $git_dir;

  {
    my $chdir_guard = pushd($git_dir);
    system(qw(git init)) and die "error running git init";
  }

  $self->deploy_schemas_at($db_root);

  my $dsnbase = "DBI:SQLite:dbname=$db_root";

  my %overrides = (
    AUTHEN_DATA_SOURCE_NAME   => "$dsnbase/authen.sqlite",
    CHECKSUMS_SIGNING_PROGRAM => "\0",
    GITROOT                   => $git_dir,
    GZIP                      => which('gzip'),
    GZIP_OPTIONS              => '',
    MLROOT                    => File::Spec->catdir($ml_root),
    ML_CHOWN_GROUP     => +(getgrgid($)))[0],
    ML_CHOWN_USER      => +(getpwuid($>))[0],
    ML_MIN_FILES       => 1,
    ML_MIN_INDEX_LINES => 1,
    MOD_DATA_SOURCE_NAME => "$dsnbase/mod.sqlite",
    PID_DIR              => $pid_dir,
  );

  local $PAUSE::Config = {
    %{ $PAUSE::Config },
    %overrides,
  };

  my $chdir_guard = pushd;

  PAUSE::mldistwatch->new->reindex;

  $code->($tmpdir) if $code;

  return PAUSE::TestPAUSE::Result->new({
    tmpdir => $tmpdir,
    config_overrides => \%overrides,
    authen_db_file   => File::Spec->catfile($db_root, 'authen.sqlite'),
    mod_db_file      => File::Spec->catfile($db_root, 'mod.sqlite'),
  });
}

1;
