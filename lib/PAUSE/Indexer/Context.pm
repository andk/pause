package PAUSE::Indexer::Context;
use v5.12.0;
use Moo;

has package_warnings => (
  is => 'bare',
  reader  => '_package_warnings',
  default => sub {  {}  },
);

sub add_package_warning {
  my ($self, $package_obj, $warning) = @_;

  my $package = $package_obj->{PACKAGE};
  my $pmfile  = $package_obj->pmfile->{PMFILE};

  my $key = "$package\0$pmfile";

  my $list = ($self->_package_warnings->{$key} //= []);
  push @$list, {
    package => $package,
    pmfile  => $pmfile,
    text    => $warning,
  };

  return;
}

sub warnings_for_all_packages {
  my ($self) = @_;

  return map {; @$_ } values $self->_package_warnings->%*;
}

sub warnings_for_package {
  my ($self, $package_name) = @_;

  return grep {; $_->{package} eq $package_name }
         map  {; @$_ } values $self->_package_warnings->%*;
}

no Moo;
1;
