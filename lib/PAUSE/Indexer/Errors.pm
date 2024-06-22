package PAUSE::Indexer::Errors;
use v5.12.0;
use warnings;

use Carp ();

use Sub::Exporter -setup => {
  exports => [ qw( DISTERROR PKGERROR ) ],
  groups  => { default => [ qw( DISTERROR PKGERROR ) ] },
};

sub dist_error;
sub pkg_error;

sub _assert_args_present {
  my ($ident, $hash, $names_demanded) = @_;

  for my $name (@$names_demanded) {
    next if exists $hash->{$name};

    Carp::confess("no $name given in PKGERROR($ident)")
  }
}

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

dist_error not_a_dist => {
  header  => 'file does not appear to be a CPAN distribution',
  body    => <<'EOF',
The file you uploaded doesn't appear to be a CPAN distribution.  Usually that
means you didn't upload a .tar.gz or .zip file.  At any rate, PAUSE can't index
it.
EOF
};

dist_error perl_unofficial => {
  header  => 'perl-like archive rejected',
  body    => <<'EOF',
The archive you uploaded has a name starting with "perl-", but doesn't appear
to be an authorized release of Perl.  Pick a different name.  If you're diong
an authorized Perl release and you see this error, contact the PAUSE admins!
EOF
};

dist_error perl_rejected => {
  header  => 'perl release archive rejected',
  body    => <<'EOF',
The archive you uploaded looks like it's meant to be a release of Perl itself.
It won't be indexed, either because you don't have permission to release Perl,
or because it looks weird in some way.  If you're doing an authorized Perl
release and you see this error, contact the PAUSE admins!
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

dist_error untar_failure => {
  header => "archive couldn't be untar-ed",
  body   => <<"EOF",
You uploaded a tar archive, but PAUSE can't untar it to index the contents.
This is pretty unusual!  Maybe you named a zip file "tar.gz" by accident.
Maybe you're using a weird (and possibly broken) version of tar.  At any rate,
PAUSE can't index this archive.
EOF
};

dist_error unstable_release => {
  header  => 'META release_status is not stable',
  body    => <<'EOF',
Your META file provides a release status other than "stable", so this
distribution will not be indexed.
EOF
};

dist_error version_dev => {
  header  => 'release has trial-release version',
  body    => <<'EOF',
The uploaded filename contains an underscore ("_") or the string "-TRIAL",
indicating that it shouldn't be indexed.
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
  header  => "Not indexed because of conflicting record in index",
  body    => sub {
    my ($arg) = @_;

    _assert_args_present(db_conflict => $arg, [ qw(package_name) ]);

    return <<"EOF"
Indexing failed because of conflicting records for $arg->{package_name}.
Please report the case to the PAUSE admins at modules\@perl.org.
EOF
  },
};

pkg_error db_error => {
  # Before PKGERROR existed, this would include the database error.  This felt
  # like a bad idea to rjbs when he refactored, so he removed it.  Easy to
  # re-add, if we want to, though!  -- rjbs, 2023-05-03
  header  => 'Not indexed because of database error',
  body    => <<'EOF',
The PAUSE indexer could not store the indexing result in the PAUSE database due
to an internal database error.  Please report this to the PAUSE admins at
modules@perl.org.
EOF
};

pkg_error dual_newer => {
  header  => 'Not indexed because of an newer dual-life module',
  body    => sub {
    my ($old) = @_;

    _assert_args_present(db_conflict => $old, [ qw(package file dist version) ]);

    return <<"EOF";
Not indexed because package $old->{package} in file $old->{file} has a dual
life in $old->{dist}.  The other version is at $old->{version}, so not indexing
seems okay.
EOF
  },
};

pkg_error dual_older => {
  header  => 'Not indexed because of an older dual-life module',
  body    => sub {
    my ($old) = @_;

    _assert_args_present(db_conflict => $old, [ qw(package file dist version) ]);

    return <<"EOF";
Not indexed because package $old->{package} in file $old->{file} seems to have
a dual life in $old->{dist}. Although the other package is at version
[$old->{version}], the indexer lets the other dist continue to be the reference
version, shadowing the one in the core.  Maybe harmless, maybe needs resolving.
EOF
  }
};

pkg_error mtime_fell => {
  header  => 'Release seems outdated',
  body    => sub {
    my ($old) = @_;

    _assert_args_present(db_conflict => $old, [ qw(package file dist version) ]);

    return <<"EOF";
Not indexed because $old->{file} in $old->{dist} also has a zero version number
and the distro has a more recent modification time.
EOF
  }
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
  header => "Not indexed because of decreasing version number",
  body   => sub {
    my ($old) = @_;

    _assert_args_present(db_conflict => $old, [ qw(package file dist version) ]);

    return <<"EOF";
Not indexed because $old->{file} in $old->{dist} has a higher version number
($old->{version})
EOF
  }
};

pkg_error version_invalid => {
  header  => 'Not indexed because version is not a valid "lax version" string.',
  body   => sub {
    my ($arg) = @_;

    _assert_args_present(db_conflict => $arg, [ qw(version) ]);

    return <<"EOF";
The version present in the file, "$arg->{version}", is not a valid lax version
string.  You can read more in "perldoc version".  This restriction would be
enforced at compile time if you put your version string within your package
declaration.
EOF
  }
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
  my ($ident, $arg) = @_;

  my $template = { $PKG_ERROR{$ident}->%* };

  unless ($template) {
    Carp::confess("requested unknown package error: $ident");
  }

  my $error = { %$template };

  if (ref $error->{body}) {
    my $body = $error->{body}->($arg);
    $error->{body} = $body;
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
