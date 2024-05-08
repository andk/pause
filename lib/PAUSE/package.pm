use strict;
use warnings;
package PAUSE::package;
use vars qw($AUTOLOAD);

use PAUSE::Logger '$Logger';

use PAUSE::mldistwatch::Constants;
use PAUSE::Indexer::Errors;
use CPAN::DistnameInfo;

=comment

Now we have a table primeur and we have a new terminology:

people in table "perms" are co-maintainers or maintainers

people in table "primeur" are maintainers

packages in table "packages" live there independently from permission
tables.

packages in table "mods" have an official owner. That one overrules
both tables "primeur" and "perms".


P1.0 If there is a registered maintainer in mods, put him into perms
     unconditionally.

P2.0 If perms knows about this package but current user is not in
     perms for this package, return.

 P2.1 but if user is primeur or perl, go on

 P2.2 but if there is no primeur, make this user primeur

P3.0 Give this user an entry in perms now, no matter how many there are.

P4.0 Work out how packages table needs to be updated.

 P4.1 We know this package: complicated UPDATE

 P4.2 We don't know it: simple INSERT



package in packages  package in primeur
         1                   1               easy         nothing add'l to do
         0                   0               easy         4.2
         1                   0               error        4.1
         0                   1           complicated(*)   4.2

(*) This happens when a package is removed from CPAN completely.


=cut

sub parent {
  my($self) = @_;
  $self->{FIO} || $self->{DIO};
}

sub pmfile { $_[0]{FIO}      }
sub dist   { $_[0]{FIO}{DIO} }
sub hub    { $_[0]{FIO}{DIO}{HUB} }

sub DESTROY {}

# package PAUSE::package;
sub new {
  my($me) = shift;
  bless { @_ }, ref($me) || $me;
}

# package PAUSE::package;
# return value nonsensical
# XXX needs case check
sub give_regdowner_perms {
  # This subroutine originally existed for interactions with the module list,
  # which was effectively made a non-feature years ago.  Its job now is to
  # ensure that new packages are given, at a minimum, the same permission as
  # those given to the main package of the distribution being uploaded.
  # -- rjbs, 2018-04-19
  my ($self, $ctx) = @_;
  my $package = $self->{PACKAGE};
  my $main_package = $self->{MAIN_PACKAGE};

  return if lc $main_package eq lc $package;

  $Logger->log("copying permissions from $main_package to $package");
  my $changer = $self->hub->permissions->plan_package_permission_copy($main_package, $package);
  $changer->();

  return;
}

# perm_check: we're both guessing and setting.

# P2.1: returns 1 if user is owner or perl; makes him
# co-maintainer at the same time

# P2.0: otherwise returns false if the package is already known in
# perms table AND the user is not among the co-maintainers

# but if the package is not yet known in the perms table this makes
# him co-maintainer AND returns 1

# these checks should be case-insensitive, so a user having permission
# on Foo is the same as having it on foo

# package PAUSE::package;
sub assert_permissions_okay {
  my ($self, $ctx) = @_;
  my $dist = $self->{DIST};
  my $package = $self->{PACKAGE};
  my $main_package = $self->{MAIN_PACKAGE};
  my $pp = $self->{PP};
  my $dbh = $self->connect;

  my($userid) = $self->{USERID};

  my $plan_set_comaint = $self->hub->permissions->plan_set_comaint($userid, $package);

  if ($self->{FIO}{DIO} && PAUSE::isa_regular_perl($dist)) {
      $plan_set_comaint ->("(perl)");
      return 1;           # P2.1, P3.0
  }

  # is uploader authorized for this package? --> case sensitive
  my $primeur = $self->hub->permissions->get_package_first_come_with_exact_case($package);
  if ($userid eq $primeur) {
      $plan_set_comaint ->("(primeur)");
      return 1;           # P2.1, P3.0
  }

  my $auth_ids = $self->hub->permissions->get_package_maintainers_list_any_case($package);

  if (@$auth_ids) {

      # we have a package that is already known

      for ($package,
            $dist,
            $pp->{infile}) {
          $_ ||= '';
      }
      $pp->{version} = '' unless defined $pp->{version}; # accept version 0

      my @owners      = map  { $_->[1] } @$auth_ids;
      my @owned       = grep { $_->[1] eq $userid  } @$auth_ids;
      my @owned_exact = grep { $_->[0] eq $package } @owned;

      if (PAUSE::isa_regular_perl($dist)) {
          # seems ok: perl is always right
      } elsif (@owned && ! @owned_exact) {
          # Case mismatch.  Let's correct.
      } elsif (! (@owned && @owned_exact)) {
          # we must not index this and we have to inform somebody
          my $owner = eval { $self->hub->permissions->get_package_first_come_any_case($package) }
                    // "unknown";

          my $error   = "not owner";

          $ctx->add_alert(qq{$error:
package[$package]
version[$pp->{version}]
file[$pp->{infile}]
dist[$dist]
userid[$userid]
owners[@owners]
owner[$owner]
});

          $ctx->abort_indexing_package($self, PKGERROR('no_permission'));
      }

  } else {

      # package has no existence in perms yet, so this guy is OK

      $plan_set_comaint ->("(uploader)");

  }

  # just for debugging
  $Logger->log_debug([
    "will consider adding to 02packages: %s", {
      package => $package,
      version => $pp->{version},
      file    => $pp->{infile},
      mtime   => $pp->{filemtime},
      dist    => $dist,
    }
  ]);

  return 1;
}

# package PAUSE::package;
sub connect {
  my($self) = @_;
  my $parent = $self->parent;
  $parent->connect;
}

# package PAUSE::package;
sub disconnect {
  my($self) = @_;
  my $parent = $self->parent;
  $parent->disconnect;
}

# package PAUSE::package;
sub mlroot {
  my($self) = @_;
  my $fio = $self->parent;
  $fio->mlroot;
}

sub _pkg_name_insane {
    # XXX should be tested
    my ($self, $ctx) = @_;

    my $package = $self->{PACKAGE};
    return $package !~ /^\w[\w\:\']*\w?\z/
        || $package !~ /\w\z/
        || $package =~ /:/ && $package !~ /::/
        || $package =~ /\w:\w/
        || $package =~ /:::/;
}

# package PAUSE::package;
sub examine_pkg {
  my ($self, $ctx) = @_;

  my $dbh = $self->connect;
  my $package = $self->{PACKAGE};
  my $dist = $self->{DIST};
  my $pp = $self->{PP};
  my $pmfile = $self->{PMFILE};

  # should they be cought earlier? Maybe.
  # but as an ultimate sanity check suggested by Richard Soderberg
  if ($self->_pkg_name_insane($ctx)) {
      $ctx->abort_indexing_package($self, "invalid package name");
  }

  # Query all users with perms for this package

  $self->assert_permissions_okay($ctx);

  # Check that package name matches case of file name
  {
    my (undef, $module) = split m{/lib/}, $self->{PMFILE}, 2;
    if ($module) {
      $module = $module =~ s{\.pm\z}{}r =~ s{/}{::}gr;

      if (lc $module eq lc $package && $module ne $package) {
        # warn "/// $self->{PMFILE} vs. $module vs. $package\n";
        $ctx->add_package_warning(
          $self,
          "Capitalization of package does not match filename!",
        );
      }
    }
  }

  # Parser problem

  if ($pp->{version} && $pp->{version} =~ /^\{.*\}$/) { # JSON parser error
      my $err = JSON::jsonToObj($pp->{version});
      if ($err->{openerr}) {
          # TODO: get $err->{openerr} back in here, I guess?
          $ctx->abort_indexing_package($self, PKGERROR('version_openerr'));
      }

      # TODO: get $err->{line} back in here, I guess?
      $ctx->abort_indexing_package($self, PKGERROR('version_parse'));
  }

  # Sanity checks
  for ($package, $pp->{version}, $dist) {
      if (!defined || /^\s*$/ || /\s/) {
          # If we got here, what on earth happened?
          $ctx->abort_indexing_package($self, PKGERROR('wtf'));
      }
  }

  $self->checkin($ctx);
  delete $self->{FIO};    # circular reference
}

sub assert_version_ok {
    my ($self, $ctx) = @_;

    return if length $self->{PP}{version} <= 16;

    $ctx->add_alert(qq{version string was too long:
package[$self->{PACKAGE}]
version[$self->{PP}{version}]
file[$self->{PP}{infile}]
dist[$self->{DIST}]
});

    $ctx->abort_indexing_package($self, PKGERROR('version_too_long'));
}

# package PAUSE::package;
sub update_package {
  # we come here only for packages that have opack and package
  my ($self, $ctx, $row) = @_;

  my $dbh = $self->connect;
  my $package = $self->{PACKAGE};
  my $dist = $self->{DIST};
  my $pp = $self->{PP};
  my $pmfile = $self->{PMFILE};
  my $fio = $self->{FIO};

  my($opack,$oldversion,$odist,$ofilemtime,$ofile) = @$row{
    qw( package version dist filemtime file )
  };

  my $old = {
    package => $opack,
    version => $oldversion,
    dist    => $odist,
    mtime   => $ofilemtime,
    file    => $ofile,
  };

  $Logger->log([ "updating old package data: %s", $old ]);

  my $MLROOT = $self->mlroot;
  my $odistmtime = (stat "$MLROOT/$odist")[9];
  my $tdistmtime = (stat "$MLROOT/$dist")[9] ;
  # decrementing Version numbers are quite common :-(
  my $ok = 0;

  my $distorperlok = File::Basename::basename($dist) !~ m|/perl|;
  # this dist is not named perl-something (lex ILYAZ)

  my $isa_regular_perl = PAUSE::isa_regular_perl($dist);

  $distorperlok ||= $isa_regular_perl;
  # or it is THE perl dist

  my($something1) = File::Basename::basename($dist) =~ m|/perl(.....)|;
  # or it is called perl-something (e.g. perl-ldap) AND...
  my($something2) = File::Basename::basename($odist) =~ m|/perl(.....)|;
  # and we compare against another perl-something AND...
  my($older_isa_regular_perl) = PAUSE::isa_regular_perl($odist);
  # the file we're comparing with is not the perl dist

  $distorperlok ||= $something1 && $something2 &&
      $something1 eq $something2 && !$older_isa_regular_perl;

  $Logger->log([
    "new package data: %s", {
      package => $package,
      version => $pp->{version},
      dist    => $dist,
      mtime   => $pp->{filemtime},
      file    => $pp->{infile},

      distorperlok => $distorperlok,
    },
  ]);

  # We don't think it's either a CPAN distribution or a perl upload.  What even
  # are we doing?  Just give up. -- rjbs, 2023-04-30
  return unless $distorperlok;

  # Until 2002-08-01 we always had
  # if >ver                                                 OK
  # elsif <ver
  # else
  #   if 0ver
  #     if <=old                                            OK
  #     else
  #   elsif =ver && <=old && ( !perl || perl && operl)      OK

  # From now we want to have the primary decision on isaperl. If it
  # is a perl, we only index if the other one is also perl or there
  # is no other. Otherwise we leave the decision tree unchanged
  # except that we can simplify the complicated last line to

  #   elsif =ver && <=old                                   OK

  # AND we need to accept falling version numbers if old dist is a
  # perl

  # relevant postings/threads:
  # http://www.xray.mpe.mpg.de/mailing-lists/perl5-porters/2002-07/msg01579.html
  # http://www.xray.mpe.mpg.de/mailing-lists/perl5-porters/2002-08/msg00062.html

  if ($isa_regular_perl) {
      $ok = $self->__do_regular_perl_update($ctx, $row, {
          oldversion  => $oldversion,
          tdistmtime  => $tdistmtime,
          odistmtime  => $odistmtime,
          opack       => $opack,
          older_isa_regular_perl => $older_isa_regular_perl,
      });
  } elsif (defined $pp->{version} && ! version::is_lax($pp->{version})) {
      $ctx->abort_indexing_package($self, PKGERROR('version_invalid', {
        version => $pp->{version}
      }));
  } elsif (CPAN::Version->vgt($pp->{version},$oldversion)) {
      # higher VERSION here
      $Logger->log([
        "package has newer version: %s", {
          dist        => $dist,
          new_version => $pp->{version},
          old_version => $oldversion,
          package => $package,
        },
      ]);

      $ok++;
  } elsif (CPAN::Version->vgt($oldversion,$pp->{version})) {
      # lower VERSION number here
      if ($odist ne $dist) {
          delete $self->dist->{CHECKINS}{ lc $package }{ $package };

          $ctx->add_alert(qq{decreasing VERSION number [$pp->{version}]
in package[$package]
dist[$dist]
oldversion[$oldversion]
pmfile[$pmfile]
}); # });

          $ctx->abort_indexing_package($self, PKGERROR('version_fell', $old));
      } elsif ($older_isa_regular_perl) {
          $ok++;          # new on 2002-08-01
      } else {
          # we get a different result now than we got in a previous run
          $ctx->add_alert("Taking back previous version calculation. odist[$odist]oversion[$oldversion]dist[$dist]version[$pp->{version}].");
          $ok++;
      }
  } else {

      # 2004-01-04: Stas Bekman asked to change logic here. Up to rev 478 we
      # did not index files with a version of 0 and with a falling timestamp.
      # These strange timestamps typically happen for developers who work on
      # more than one computer. Files that are not changed between releases
      # keep two different timestamps from some arbitrary checkout in the past.
      # Stas correctly suggests, we should check these cases for distmtime, not
      # filemtime.

      if ($pp->{version} eq "undef"||$pp->{version} == 0) { # no version here,
          if ($tdistmtime >= $odistmtime) { # but younger or same-age dist
              $Logger->log([
                "no version, but new file is newer than stored: %s", {
                  package => $package,
                  new     => { dist => $odist, mtime => $tdistmtime },
                  old     => { dist => $odist, mtime => $odistmtime },
                },
              ]);
              $ok++;
          } else {
              $ctx->abort_indexing_package($self, PKGERROR('mtime_fell', $old));
          }
      } elsif (CPAN::Version->vcmp($pp->{version}, $oldversion)==0) {
          # equal version here
          # XXX needs better logging message -- dagolden, 2011-08-13
          if ($tdistmtime >= $odistmtime) { # but younger or same-age dist
              $Logger->log([
                "versions are equal, but new file newer than stored: %s", {
                  package => $package,
                  new     => { dist => $odist, mtime => $tdistmtime },
                  old     => { dist => $odist, mtime => $odistmtime },
                },
              ]);
              $ok++;
          } else {
              $Logger->log([
                "versions are equal, and new file older than stored: %s", {
                  package => $package,
                  new     => { dist => $odist, mtime => $tdistmtime },
                  old     => { dist => $odist, mtime => $odistmtime },
                },
              ]);
              $ctx->abort_indexing_package($self, PKGERROR('mtime_fell', $old));
          }
      } else {
          $Logger->log(
            "nothing interesting in dist [$dist] package [$package]"
          );
      }
  }

  # If we're not okay yet, we're not going to become okay going forward.
  return unless $ok;

  if ($self->{FIO}{DIO}{VERSION_FROM_META_OK}) {
      # nothing to argue at the moment, e.g. lib_pm.PL
  } elsif (
      ! $pp->{basename_matches_package}
      &&
      PAUSE->basename_matches_package($ofile,$package)
  ) {
      $Logger->log([
        "warning: basename does not match package, but it used to: %s", {
          package => $package,
          old_file => $ofile,
          new_file => $pp->{infile},
        }
      ]);

      return;
  }

  my ($pkg_recs) = $dbh->selectall_arrayref(
      qq{
          SELECT package, version, dist
          FROM packages
          WHERE lc_package = ?
      },
      { Slice => {} },
      lc $package,
  );

  if (@$pkg_recs > 1) {
      $Logger->log([
          "conflicting records exist in packages table, won't index: %s",
          [ @$pkg_recs ],
      ]);

      $ctx->abort_indexing_package($self, PKGERROR('db_conflict'));
  }

  $self->assert_version_ok($ctx);

  $Logger->log([
    "updating packages: %s", {
      package  => $package,
      version  => $pp->{version},
      dist     => $dist,
      infile   => $pp->{infile},
      filetime => $pp->{filemtime},
      disttime => $self->dist->{TIME},
    },
  ]);

  my $rows_affected = eval {
      $dbh->do(
          q{
            UPDATE  packages
            SET     package = ?, version = ?, dist = ?, file = ?,
                    filemtime = ?, pause_reg = ?
            WHERE lc_package = ?
          },
          undef,
          $package, $pp->{version}, $dist, $pp->{infile},
          $pp->{filemtime}, $self->dist->{TIME},
          lc $package,
      );
  };

  unless ($rows_affected) {
      my $dbherrstr = $dbh->errstr;
      $ctx->abort_indexing_package($self, PKGERROR('db_error'));
  }

  $ctx->record_package_indexing($self);
}

sub __do_regular_perl_update {
    my ($self, $ctx, $old_row, $arg) = @_;

    my ($opack, $oldversion, $odist, $ofilemtime, $ofile) = @$old_row{
      qw( package version dist filemtime file )
    };

    my $old = {
      package => $opack,
      version => $oldversion,
      dist    => $odist,
      mtime   => $ofilemtime,
      file    => $ofile,
    };

    my $older_isa_regular_perl = $arg->{older_isa_regular_perl};

    my $odistmtime  = $arg->{odistmtime};
    my $tdistmtime  = $arg->{tdistmtime};

    my $pp      = $self->{PP};
    my $package = $self->{PACKAGE};

    my $ok = 0;

    if ($older_isa_regular_perl) {
        if (CPAN::Version->vgt($pp->{version},$oldversion)) {
            $ok++;
        } elsif (CPAN::Version->vgt($oldversion,$pp->{version})) {
        } elsif (CPAN::Version->vcmp($pp->{version},$oldversion)==0
                  &&
                  $tdistmtime >= $odistmtime
        ) {
            $ok++;
        }
    } else {
        if (CPAN::Version->vgt($pp->{version},$oldversion)) {
            $ctx->abort_indexing_package($self, PKGERROR('dual_older', $old));
        } else {
            $ctx->abort_indexing_package($self, PKGERROR('dual_newer', $old));
        }
    }

    return $ok;
}

# package PAUSE::package;
sub insert_into_package {
  my ($self, $ctx) = @_;
  my $dbh = $self->connect;
  my $package = $self->{PACKAGE};
  my $dist = $self->{DIST};
  my $pp = $self->{PP};
  my $pmfile = $self->{PMFILE};
  my $distname = CPAN::DistnameInfo->new($dist)->dist;
  my $query = qq{
    INSERT INTO packages
      (package, lc_package, version, dist, file, filemtime, pause_reg, distname)
    VALUES (?,?,?,?,?,?,?,?)
  };

  $Logger->log([
    "inserting package: %s", {
      package   => $package,
      version   => $pp->{version},
      dist      => $dist,
      file      => $pp->{infile},
      filetime  => $pp->{filemtime},
      disttime  => $self->dist->{TIME},
    }
  ]);

  $self->assert_version_ok($ctx);
  $dbh->do($query,
            undef,
            $package,
            lc $package,
            $pp->{version},
            $dist,
            $pp->{infile},
            $pp->{filemtime},
            $self->dist->{TIME},
            $distname,
          );

  $ctx->record_package_indexing($self);
}

# package PAUSE::package;
# returns always the return value of print, so basically always 1
sub checkin_into_primeur {
  my ($self, $ctx) = @_;
  my $dbh = $self->connect;
  my $package = $self->{PACKAGE};
  my $dist = $self->{DIST};
  my $pp = $self->{PP};
  my $pmfile = $self->{PMFILE};

  # we cannot do that yet, first we must fill primeur with the
  # values we believe are correct now.

  # We come here, no matter if this package is in primeur or not. We
  # know, it must get in there if it isn't yet. No update, just an
  # insert, please. Should be similar to give_regdowner_perms(), but
  # this time with this user.

  # print ">>>>>>>>checkin_into_primeur not yet implemented<<<<<<<<\n";

  my $userid;
  my $dio = $self->dist;

  if (defined $dio->{META_CONTENT}{x_authority}) {
      $userid = $dio->{META_CONTENT}{x_authority};
      $userid =~ s/^cpan://i;
      # FIXME: if this ends up being blank we should probably die?
      # validate userid existing
  } else {
      if (exists $dio->{META_CONTENT}{x_authority}) {
          $Logger->log("x_authority was present but undefined; ignoring!");
      }
      # look to the existing main package.
      if(lc($self->{MAIN_PACKAGE}) eq lc($package)) {
          $userid = $self->{USERID} or die;
      } else {
          $userid = $self->hub->permissions->get_package_first_come_any_case($self->{MAIN_PACKAGE});
          $userid = $self->{USERID} unless $userid;
          die "Shouldn't reach here: userid unknown" unless $userid;
      }
  }

  Carp::confess("no userid!?") unless defined $userid;

  my $plan = $self->hub->permissions->plan_set_first_come($userid, $package);
  $plan->();

  return 1;
}

# package PAUSE::package;
sub checkin {
  my ($self, $ctx) = @_;
  my $dbh = $self->connect;
  my $package = $self->{PACKAGE};
  my $dist = $self->{DIST};
  my $pp = $self->{PP};
  my $pmfile = $self->{PMFILE};

  # Copy permissions from main module to subsidiary modules.
  $self->give_regdowner_perms($ctx);

  $self->dist->{CHECKINS}{ lc $package }{$package} = $self->{PMFILE};

  my $row = $dbh->selectrow_hashref(
    qq{
      SELECT package, version, dist, filemtime, file
      FROM packages
      WHERE lc_package = ?
    },
    undef,
    lc $package
  );

  if ($row) {
      # We know this package from some time ago
      $self->update_package($ctx, $row);
  } else {
      # we hear for the first time about this package
      $self->insert_into_package($ctx);
  }

  # my $status = $self->get_index_status_status($ctx);
  # if (! $status or $status == PAUSE::mldistwatch::Constants::OK) {
      $self->checkin_into_primeur($ctx); # called in void context!
  # }

  return;
}

1;
