package PAUSE::TestPAUSE;
use Moose;
use MooseX::StrictConstructor;

use File::Path qw(make_path);
use File::Temp ();
use File::Copy::Recursive qw(dircopy);

use PAUSE;
use PAUSE::mldistwatch;

use namespace::autoclean;

has author_root => (
  is  => 'ro',
  isa => 'Str',
  required => 1,
);

sub deploy_schemas_at {
  my ($self, $dir) = @_;

  # DESPERATELY EVIL -- rjbs, 2011-08-13
  `sqlite3 "$dir/authen.sqlite" < doc/schemas/authen_pause.schema.sqlite`;
  `sqlite3 "$dir/mod.sqlite"    < doc/schemas/mod.schema.sqlite`;
}

sub test {
  my ($self, $code) = @_;

  my $tmpdir = File::Temp->newdir;

  my $cpan_root = File::Spec->catdir($tmpdir, 'cpan');
  my $ml_root = File::Spec->catdir($cpan_root, qw(authors id));

  make_path( File::Spec->catdir($cpan_root, 'modules') );

  dircopy($self->author_root, $ml_root);

  mkdir File::Spec->catdir($tmpdir, 'db');
  my $db_root = File::Spec->catdir($tmpdir, 'db');
  my $dsnbase = "DBI:SQLite:dbname=$db_root";

  local $PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME} = "$dsnbase/authen.sqlite";
  local $PAUSE::Config->{MOD_DATA_SOURCE_NAME} = "$dsnbase/mod.sqlite";

  $self->deploy_schemas_at($db_root);

  local $PAUSE::Config->{MLROOT}  = File::Spec->catdir($ml_root);

  local $PAUSE::Config->{PID_DIR} = File::Spec->catdir($tmpdir, 'run');
  mkdir $PAUSE::Config->{PID_DIR};

  local $PAUSE::Config->{ML_MIN_FILES} = 1;
  local $PAUSE::Config->{ML_MIN_INDEX_LINES} = 1;

  local $PAUSE::Config->{ML_CHOWN_USER}  = +(getpwuid($>))[0];
  local $PAUSE::Config->{ML_CHOWN_GROUP} = +(getgrgid($)))[0];

  local $PAUSE::Config->{ML_MAILER} = 'testfile';

  PAUSE::mldistwatch->new->reindex;

  $code->($tmpdir) if $code;

  return $tmpdir;
}

1;
