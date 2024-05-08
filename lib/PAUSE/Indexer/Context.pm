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

  $Logger->log([
    "adding package warning to %s: %s",
    $package_obj->{PACKAGE},
    $list->[-1],
  ]);

  return;
}

has package_status => (
  is => 'bare',
  reader  => '_package_status',
  default => sub {  {}  },
);

sub _set_package_error {
  my ($self, $package_obj, $status) = @_;

  $self->_package_status->{ $package_obj->{PACKAGE} } = {
    is_success  => 0,
    filename    => $package_obj->{PP}{infile},
    version     => $package_obj->{PP}{version},
    header      => $status->{header},
    body        => $status->{body},
    package     => $package_obj->{PACKAGE},
  };

  $Logger->log([
    "set error status for %s",
    $package_obj->{PACKAGE},
  ]);

  return;
}

sub record_package_indexing {
  my ($self, $package_obj) = @_;

  $self->_package_status->{ $package_obj->{PACKAGE} } = {
    is_success  => 1,
    filename    => $package_obj->{PP}{infile},
    version     => $package_obj->{PP}{version},
    header      => "Indexed successfully",
    body        => "The package was indexed successfully.",
    package     => $package_obj->{PACKAGE},
  };

  $Logger->log([
    "set OK status for %s",
    $package_obj->{PACKAGE},
  ]);

  return;
}

sub package_statuses {
  my ($self) = @_;

  my %stash = %{ $self->_package_status };
  return @stash{ sort keys %stash };
}

sub abort_indexing_package {
  my ($self, $package_obj, $error) = @_;

  $Logger->log("abort indexing $package_obj->{PACKAGE}");

  $self->_set_package_error($package_obj, $error);

  die PAUSE::Indexer::Abort::Package->new({
    message => $error->{header},
    public  => 1,
  });
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

sub add_alert {
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

sub all_dist_errors {
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
