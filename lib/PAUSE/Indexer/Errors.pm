package PAUSE::Indexer::Errors;
use v5.12.0;
use warnings;

use Sub::Exporter -setup => {
  exports => [ 'ERROR' ],
  groups  => { default => [ 'ERROR' ] },
};

my %ERROR;

sub public_error {
  my ($name, $arg) = @_;
  $ERROR{$name} = {
    ident   => $name,
    public  => 1,
    %$arg,
  };
}

public_error blib => {
  header  => 'archive contains a "blib" directory',
  body    => <<'EOF'
The distribution contains a blib/ directory and is therefore not being indexed.
Hint: try 'make dist'.
EOF
};

public_error multiroot => {
  header  => 'archive has multiple roots',
  body    => sub {
    my ($dist) = @_;
    return <<"EOF"
The distribution does not unpack into a single directory and is therefore not
being indexed. Hint: try 'make dist' or 'Build dist'. (The directory entries
found were: @{$dist->{HAS_MULTIPLE_ROOT}})
EOF
  },
};

public_error no_distname_permission => {
  header  => 'missing permissions on distname package',
  body    => sub {
    my ($dist) = @_;

    my $pkg = $dist->_package_governing_permission;

    return <<"EOF"
You appear to be missing a .pm file containing a package matching the dist
name.  For this distribution, that package would be called $pkg.  Adding this
may solve your issue. Or maybe it is the other way round and a different
distribution name could be chosen, matching a package you are shipping.
EOF
  },
};

public_error no_meta => {
  header  => "no META.yml or META.json found",
  body    => <<'EOF',
Your archive didn't contain a META.json or META.yml file.  You need to include
at least one of these.  A CPAN distribution building tool like
ExtUtils::MakeMaker can help with this.
EOF
};

public_error single_pm => {
  header  => 'dist is a single-.pm-file upload',
  body    => <<"EOF",
You've uploaded a compressed .pm file without a META.json, a build tool, or the
other things you need to be a CPAN distribution.  This was once permitted, but
no longer is.  Please use a CPAN distribution building tool.
EOF
};

public_error unstable_release => {
  header  => 'META release_status is not stable',
  body    => <<'EOF',
Your META file provides a release status other than "stable", so this
distribution will not be indexed.
EOF
};

public_error worldwritable => {
  header  => 'archive has world writable files',
  body    => sub {
    my ($dist) = @_;
    return <<"EOF"
The distribution contains the following world writable directories or files and
is therefore considered a security breach and as such not being indexed:
@{$dist->{HAS_WORLD_WRITABLE}}
EOF
  },
};

public_error xact_fail => {
  header => "ERROR: Database error occurred during index update",
  body   => <<'EOF',
This distribution was not indexed due to database errors.  You can request
another indexing attempt be made by logging into https://pause.perl.org/
EOF
};

sub ERROR {
  my ($ident) = @_;

  my $error = PAUSE::Indexer::Errors->error_named($ident);
  unless ($error) {
    Carp::confess("requested unknown error: $ident");
  }

  return $error;
}

sub error_named {
  my ($self, $ident) = @_;

  return $ERROR{$ident};
}

1;
