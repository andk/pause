package PAUSE::Indexer::Context;
use v5.12.0;
use Moo;

use PAUSE::Indexer::Abort::Dist;
use PAUSE::Indexer::Abort::Package;
use PAUSE::Indexer::Errors;
use PAUSE::Logger '$Logger';

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

  return map {; @$_ } values %{ $self->_package_warnings };
}

sub warnings_for_package {
  my ($self, $package_name) = @_;

  return grep {; $_->{package} eq $package_name }
         $self->warnings_for_all_packages;
}

has alerts => (
  is      => 'bare',
  reader  => '_alerts',
  default => sub {  []  },
);

sub alert {
  my ($self, $alert) = @_;
  $alert =~ s/\v+\z//;

  push @{ $self->_alerts }, $alert;
  return;
}

sub all_alerts {
  my ($self) = @_;
  return @{ $self->_alerts };
}

has dist_errors => (
  is      => 'bare',
  reader  => '_dist_errors',
  default => sub {  []  },
);

sub add_dist_error {
  my ($self, $error) = @_;

  $error = ref $error ? $error : { ident => $error, message => $error };

  $Logger->log("adding dist error: " . ($error->{ident} // $error->{message}));
  push @{ $self->_dist_errors }, $error;

  return $error;
}

sub dist_errors {
  my ($self) = @_;
  return @{ $self->_dist_errors };
}

sub abort_indexing_dist {
  my ($self, $error) = @_;

  $error = $self->add_dist_error($error);

  die PAUSE::Indexer::Abort::Dist->new({
    message => $error->{message},
    public  => $error->{public},
  });
}

no Moo;
1;
