use 5.008001;
use strict;
use warnings;

package PAUSE::PermsManager;

use Moo;
use PAUSE ();

has dbh_callback => (
  is => 'ro',
  isa => sub { die "dbh_callback must be a coderef" unless ref $_[0] eq 'CODE' },
  required => 1,
);

# returns first_come user for a package or the empty string. If there are
# more than one matches, only the first is returned
sub get_package_first_come_any_case {
  my ($self, $pkg) = @_;
  my $dbh = $self->dbh_callback->();
  my $query = "SELECT package, userid FROM primeur where LOWER(package) = LOWER(?)";
  my $owner = $dbh->selectrow_arrayref($query, undef, $pkg);
  return $owner->[1] if $owner;
  return "";
}

# returns first_come user for a package or the empty string
sub get_package_first_come_with_exact_case {
  my ($self, $pkg) = @_;
  my $dbh = $self->dbh_callback->();
  my $query = "SELECT package, userid FROM primeur where package = ?";
  my $owner = $dbh->selectrow_arrayref($query, undef, $pkg);
  return $owner->[1] if $owner;
  return "";
}

sub get_package_maintainers_list_any_case {
  my ($self, $package) = @_;
  my $dbh = $self->dbh_callback->();
  my $sql = qq{
    SELECT package, userid
      FROM   primeur
      WHERE  LOWER(package) = LOWER(?)
      UNION
    SELECT package, userid
      FROM   perms
      WHERE  LOWER(package) = LOWER(?)
  };
  my @args = ($package) x 2;
  return $dbh->selectall_arrayref($sql, undef, @args);
}

# returns callback to copy permissions from one package to another;
# currently doesn't address primeur or *remove* excess permissions from
# the destination. I.e. after running this, perms on the destination will
# be a superset of the source.
sub plan_package_permission_copy {
  my ( $self, $src, $dst ) = @_;

  return sub {
    my $dbh = $self->dbh_callback->();
    local($dbh->{RaiseError}) = 0;
    my $src_permissions = $dbh->selectall_arrayref(
        q{
        SELECT userid
        FROM   perms
        WHERE  LOWER(package) = LOWER(?)
        },
        { Slice => {} },
        $src,
        );

    # TODO: correctly set first-come as well

    # TODO: drop perms on the destination before copying so they are
    # actually equal

    # TODO: return if they're already equal permissions -- rjbs, 2018-04-19

    for my $row (@$src_permissions) {
      my ($mods_userid) = $row->{userid};
      # we disable errors so that the insert emulates an upsert
      local ( $dbh->{RaiseError} ) = 0;
      local ( $dbh->{PrintError} ) = 0;
      my $query = "INSERT INTO perms (package, userid) VALUES (?,?)";
      my $ret   = $dbh->do( $query, {}, $dst, $mods_userid );
      my $err   = "";
      $err = $dbh->errstr unless defined $ret;
      $ret ||= "";
      $self->verbose( 1,
          "Insert into perms package[$dst]mods_userid"
          . "[$mods_userid]ret[$ret]err[$err]\n" );
    }

    return 1;
  }
}

# returns a callback to set first_come permissions on a package
sub plan_set_first_come {
  my ($self, $userid, $package) = @_;

  return sub {
    my $dbh = $self->dbh_callback->();

    # ensure first-come also is in perms
    $self->plan_set_comaint($userid, $package)->();

    # we disable errors so that the insert emulates an upsert
    local ( $dbh->{RaiseError} ) = 0;
    local ( $dbh->{PrintError} ) = 0;
    my $ret = $dbh->do("INSERT INTO primeur (package, userid) VALUES (?,?)", undef, $package, $userid);
    my $err = $@;
    $ret //= "";
    $self->verbose(1,
                  "Inserted into primeur package[$package]userid[$userid]ret[$ret]".
                  "err[$err]\n");
    return 1;
  };
}

# returns a callback to set comaint permissions on a package
sub plan_set_comaint {
  my ($self, $userid, $package) = @_;

  Carp::confess("can't plan to set comaint to undef") unless defined $userid;

  return sub {
    my $dbh = $self->dbh_callback->();
    my $log_prefix = shift || "";
    $log_prefix .= " " if length $log_prefix;
    # we disable errors so that the insert emulates an upsert
    local ( $dbh->{RaiseError} ) = 0;
    local ( $dbh->{PrintError} ) = 0;
    my $ret = $dbh->do("INSERT INTO perms (package, userid) VALUES (?,?)", undef, $package, $userid);
    my $err = $@;
    $ret //= "";
    $self->verbose(1,
                  "${log_prefix}Inserted into perms package[$package]userid[$userid]ret[$ret]".
                  "err[$err]\n");
    return 1;
  };
}

sub userid_has_permissions_on_package {
  my ($self, $userid, $package) = @_;

  if ($package eq 'perl') {
    return PAUSE->user_has_pumpking_bit($userid);
  }

  my $dbh = $self->dbh_callback->();

  my ($has_perms) = $dbh->selectrow_array(
    qq{
      SELECT COUNT(*) FROM perms
      WHERE userid = ? AND LOWER(package) = LOWER(?)
    },
    undef,
    $userid, $package,
  );

  my ($has_primary) = $dbh->selectrow_array(
    qq{
      SELECT COUNT(*) FROM primeur
      WHERE userid = ? AND LOWER(package) = LOWER(?)
    },
    undef,
    $userid, $package,
  );

  return($has_perms || $has_primary);
}

sub canonicalize_module_casing {
  my ($self, $package) = @_;

  my $dbh = $self->dbh_callback->();
  my $users = $dbh->selectall_arrayref(
    qq{
      SELECT perms.userid, COUNT(primeur.userid) AS is_primary
      FROM perms
      LEFT JOIN primeur
        ON  LOWER(primeur.package) = LOWER(perms.package)
        AND primeur.userid = perms.userid
      WHERE LOWER(perms.package) = LOWER(?)
      GROUP BY perms.userid, LOWER(perms.package)
    },
    { Slice => {} },
    $package,
  );

  $dbh->do(
    qq{DELETE FROM perms   WHERE LOWER(package) = LOWER(?)},
    undef,
    $package,
  );

  $dbh->do(
    qq{DELETE FROM primeur WHERE LOWER(package) = LOWER(?)},
    undef,
    $package,
  );

  for my $user (@$users) {
    $dbh->do(
      "INSERT INTO perms (package, userid) VALUES (?, ?)",
      undef,
      $package, $user->{userid},
    );

    if ($user->{is_primary}) {
      $dbh->do(
        "INSERT INTO primeur (package, userid) VALUES (?, ?)",
        undef,
        $package, $user->{userid},
      );
    }
  }

  $dbh->do(
    qq{
      UPDATE packages SET package = ? WHERE LOWER(package) = LOWER(?);
    },
    undef,
    ($package) x 2,
  );

  return;
}

sub verbose {
    my ($self, $level, @what) = @_;
    PAUSE->log($self, $level, @what);
}

1;

# Local Variables:
# mode: cperl
# cperl-indent-level: 2
# End:
# vim: set ts=2 sts=2 sw=2 et tw=75:
