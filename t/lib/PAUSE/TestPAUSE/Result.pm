package PAUSE::TestPAUSE::Result;
use Moose;
use MooseX::StrictConstructor;

use DBI;
use Parse::CPAN::Packages;
use Test::Deep qw(cmp_deeply superhashof methods);
use Test::More;

use namespace::autoclean;

has tmpdir => (
  is     => 'ro',
  isa    => 'Object',
  required => 1,
);

has config_overrides => (
  reader   => '_config_overrides',
  isa      => 'HashRef',
  required => 1,
);

has [ qw(authen_db_file mod_db_file) ] => (
  is  => 'ro',
  isa => 'Str',
  required => 1,
);

sub __connect {
  my ($self, $file) = @_;

  return DBI->connect(
    'dbi:SQLite:dbname=' . $file,
    undef,
    undef,
  ) || die "can't connect to db at $file: $DBI::errstr";
}

sub connect_authen_db {
  my ($self) = @_;
  return $self->__connect( $self->authen_db_file );
}

sub connect_mod_db {
  my ($self) = @_;
  return $self->__connect( $self->mod_db_file );
}

sub packages_data {
  my ($self) = @_;

  return Parse::CPAN::Packages->new(
    q{} . $self->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
  );
}

sub package_list_ok {
  my ($self, $want) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $pkg_rows = $self->connect_mod_db->selectall_arrayref(
    'SELECT * FROM packages ORDER BY package, version',
    { Slice => {} },
  );

  cmp_deeply(
    $pkg_rows,
    [ map {; superhashof($_) } @$want ],
    "we db-inserted exactly the dists we expected to",
  ) or diag explain($pkg_rows);

  my $p = $self->packages_data;

  my @packages = sort { $a->package cmp $b->package } $p->packages;

  cmp_deeply(
    \@packages,
    [ map {; methods(%$_) } @$want ],
    "we built exactly the 02packages we expected",
  ) or diag explain(\@packages);
}

1;
