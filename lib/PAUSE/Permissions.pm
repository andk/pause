use 5.008001;
use strict;
use warnings;

package PAUSE::Permissions;

use DBI;
use Moo;
use PAUSE ();

has dbh => (
  is => 'lazy',
);

sub _build_dbh {
  my ($self) = @_;
  return PAUSE::dbh("mod");
}

sub userid_has_permissions_on_package {
  my ($self, $userid, $package) = @_;

  if ($package eq 'perl') {
    return PAUSE->user_has_pumpking_bit($userid);
  }

  my $dbh = $self->dbh;

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

1;

# Local Variables:
# mode: cperl
# cperl-indent-level: 2
# End:
# vim: set ts=2 sts=2 sw=2 et tw=75:
