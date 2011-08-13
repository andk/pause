package PAUSE::TestPAUSE::Result;
use Moose;
use MooseX::StrictConstructor;

use Path::Class;

use namespace::autoclean;

has tmpdir => (
  reader => '_tmpdir_obj',
  isa    => 'Object',
  required => 1,
);

sub tmpdir {
  my ($self) = @_;
  return dir($self->_tmpdir_obj);
}

has config_overrides => (
  reader   => '_config_overrides',
  isa      => 'HashRef[Str]',
  required => 1,
);

1;
