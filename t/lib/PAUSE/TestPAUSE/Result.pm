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

sub p6dists_ok {
  my ($self, $want) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $pkg_rows = $self->connect_mod_db->selectall_arrayref(
    'SELECT * FROM p6dists ORDER BY name, ver',
    { Slice => {} },
  );

  cmp_deeply(
    $pkg_rows,
    [ map {; superhashof($_) } @$want ],
    "we db-inserted exactly the dists we expected to",
  ) or diag explain($pkg_rows);
}

sub perm_list_ok {
  my ($self, $want) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $index_06 = $self->tmpdir->subdir(qw(cpan modules))
                 ->file(qw(06perms.txt.gz));

  our $GZIP = $PAUSE::Config->{GZIP_PATH};
  open my $fh, "$GZIP --stdout --uncompress $index_06|"
    or die "can't open $index_06 for reading with gip: $!";

  my (@header, @data);
  my $module;
  my %permissions;
  while (<$fh>) {
    push(@header, $_), next if 1../^\s*$/;
    chomp;
    my ($m, $u, $p) = split(/,/, $_);
    if($p eq 'c') {
      push @{$permissions{$m}->{$p}}, $u;
    } else {
      $permissions{$m}->{$p} = $u;
    }
  }

  is_deeply(\%permissions, $want, "permissions look correct in 06perms")
  or diag explain(\%permissions);
}

has deliveries => (
  isa => 'ArrayRef',
  required => 1,
  traits   => [ 'Array' ],
  handles  => { deliveries => 'elements' },
);

sub email_ok {
  my ($self, $want) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my @deliveries = sort {
    $a->{email}->get_header('Subject') cmp $b->{email}->get_header('Subject')
  } $self->deliveries;

  subtest "emails sent during this run" => sub {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is(@deliveries, @$want, "as many emails as expected: " . @$want);
  };

  for my $test (@$want) {
    my $delivery = shift @deliveries;
    if ($test->{subject}) {
      is(
        $delivery->{email}->get_header('Subject'),
        $test->{subject},
        "Got email: $test->{subject}",
      );
    }

    for (@{ $test->{callbacks} || [] }) {
      local $Test::Builder::Level = $Test::Builder::Level + 1;
      $_->($delivery);
    }
  }
}

1;
