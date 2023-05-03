package PAUSE::Indexer::Errors;
use v5.12.0;
use warnings;

use Sub::Exporter -setup => {
  exports => [ qw( DISTERROR PKGERROR ) ],
  groups  => { default => [ qw( DISTERROR PKGERROR ) ] },
};

sub dist_error;
sub pkg_error;

dist_error blib => {
  header  => 'archive contains a "blib" directory',
  body    => <<'EOF'
The distribution contains a blib/ directory and is therefore not being indexed.
Hint: try 'make dist'.
EOF
};

dist_error multiroot => {
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

dist_error no_distname_permission => {
  header  => 'missing permissions on distname package',
  body    => sub {
    my ($dist) = @_;

    my $pkg = $dist->_package_governing_permission;

    return <<"EOF"
This distribution name will only be indexed when uploaded by users with
permission for the package $pkg.  Either someone else has ownership over that
package name, or this is a brand new distribution and that package name was
neither listed in the 'provides' field in the META file nor found inside the
distribution's modules.  Therefore, no modules will be indexed.  Adding a
package called $pkg may solve your issue, or instead you may wish to change the
name of your distribution.
EOF
  },
};

dist_error no_meta => {
  header  => "no META.yml or META.json found",
  body    => <<'EOF',
Your archive didn't contain a META.json or META.yml file.  You need to include
at least one of these.  A CPAN distribution building tool like
ExtUtils::MakeMaker can help with this.
EOF
};

dist_error single_pm => {
  header  => 'dist is a single-.pm-file upload',
  body    => <<"EOF",
You've uploaded a compressed .pm file without a META.json, a build tool, or the
other things you need to be a CPAN distribution.  This was once permitted, but
no longer is.  Please use a CPAN distribution building tool.
EOF
};

dist_error unstable_release => {
  header  => 'META release_status is not stable',
  body    => <<'EOF',
Your META file provides a release status other than "stable", so this
distribution will not be indexed.
EOF
};

dist_error worldwritable => {
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

dist_error xact_fail => {
  header => "ERROR: Database error occurred during index update",
  body   => <<'EOF',
This distribution was not indexed due to database errors.  You can request
another indexing attempt be made by logging into https://pause.perl.org/
EOF
};

pkg_error bad_package_name => {
  header  => 'Not indexed because of invalid package name.',
  body    => <<'EOF',
This package wasn't indexed because its name doesn't conform to standard
naming.  Basically:  one or more valid identifiers, separated by double colons
(::).
EOF
};

pkg_error db_conflict => {
  # TODO bring back $package
  header  => "Not indexed because of conflicting record in index",
  body    => <<"EOF"
Indexing failed because of conflicting records for \$package.  Please report
the case to the PAUSE admins at modules\@perl.org.
EOF
};

pkg_error db_error => {
  # TODO bring back db error string?  seems weird -- rjbs, 2023-05-01
  header  => 'Not indexed because of database error',
  body    => <<'EOF',
The PAUSE indexer could not store the indexing result in the PAUSE database due
to an internal database error.  Please report this to the PAUSE admins at
modules@perl.org.
EOF
};

pkg_error dual_newer => {
  # TODO bring back parameters
  header  => 'Not indexed because of an newer dual-life module',
  body    => <<'EOF',
Not indexed because package $opack in file $ofile has a dual life in $odist.
The other version is at $oldversion, so not indexing seems okay.
EOF
};

pkg_error dual_older => {
  # TODO bring back parameters
  header  => 'Not indexed because of an older dual-life module',
  body    => <<'EOF',
Not indexed because package $opack in file $ofile seems to have a dual life in
$odist. Although the other package is at version [$oldversion], the indexer
lets the other dist continue to be the reference version, shadowing the one in
the core.  Maybe harmless, maybe needs resolving.
EOF
};

pkg_error mtime_fell => {
  # TODO bring back ofile/odist in body
  header  => 'Release seems outdated',
  body    => q{Not indexed because $ofile in $odist also has a zero version
               number and the distro has a more recent modification time.},
};

pkg_error no_permission => {
  header  => 'Not indexed because the required permissions were missing.',
  body    => <<'EOF',
This package wasn't indexed because you don't have permission to use this
package name.  Hint: you can always find the legitimate maintainer(s) on PAUSE
under "View Permissions".
EOF
};

pkg_error version_fell => {
  # TODO bring back "file in $dist", make the q{...} a qq{...}
  header => "Not indexed because of decreasing version number",
  body   => q{Not indexed because $ofile in $odist has a higher version number
              ($oldversion)},
};

pkg_error version_invalid => {
  # TODO put back $version itself?  It's already in the report.
  # -- rjbs, 2023-05-01
  header  => 'Not indexed because version is not a valid "lax version" string.',
  body    => undef,
};

pkg_error version_openerr => {
  header  => 'Not indexed because of version handling error.',
  body    => <<'EOF',
The PAUSE indexer was not able to read the file.
EOF
};

pkg_error version_parse => {
  header  => 'Not indexed because of version parsing error.',
  body    => <<'EOF',
The PAUSE indexer was not able to parse the file.

Note: the indexer is running in a Safe compartement and cannot provide the full
functionality of perl in the VERSION line. It is trying hard, but sometime it
fails. As a workaround, please consider writing a META.yml that contains a
"provides" attribute, or contact the CPAN admins to investigate (yet another)
workaround against "Safe" limitations.
EOF
};

pkg_error version_too_long => {
  header  => 'Not indexed because the version string was too long.',
  body    => <<'EOF',
The maximum length of a version string is 16 bytes, which is already quite
long.  Please consider picking a shorter version.
EOF
};

pkg_error wtf => {
  header  => 'Not indexed: something surprising happened.',
  body    => <<'EOF',
The PAUSE indexer couldn't index this package.  It ended up with a weird
internal state, like thinking your package name was empty or your version was
undefined.  If you see this, you should probably contact the PAUSE admins.
EOF
};

my %DIST_ERROR;
my %PKG_ERROR;

sub DISTERROR {
  my ($ident) = @_;

  my $error = $DIST_ERROR{$ident};
  unless ($error) {
    Carp::confess("requested unknown distribution error: $ident");
  }

  return $error;
}

sub PKGERROR {
  my ($ident) = @_;

  my $error = $PKG_ERROR{$ident};
  unless ($error) {
    Carp::confess("requested unknown package error: $ident");
  }

  return $error;
}

sub dist_error {
  my ($name, $arg) = @_;
  $DIST_ERROR{$name} = {
    ident   => $name,
    public  => 1,
    %$arg,
  };
}

sub pkg_error {
  my ($name, $arg) = @_;
  $PKG_ERROR{$name} = {
    ident   => $name,
    public  => 1,
    %$arg,
  };
}

1;
