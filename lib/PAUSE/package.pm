use strict;
use warnings;
package PAUSE::package;
use vars qw($AUTOLOAD);
use PAUSE::mldistwatch::Constants;
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

sub verbose {
  my($self,$level,@what) = @_;
  PAUSE->log($self, $level, @what);
}

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
sub alert {
  my $self = shift;
  my $what = shift;
  my $parent = $self->parent;
  $parent->alert($what);
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
  my $self = shift;
  my $package = $self->{PACKAGE};
  my $main_package = $self->{MAIN_PACKAGE};

  return if lc $main_package eq lc $package;

  $self->verbose(1, "Granting permissions of main_mackage[$main_package] to package[$package]");
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
sub perm_check {
  my $self = shift;
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
          my $message = qq{Not indexed because permission missing.
Current registered primary maintainer is $owner.
Hint: you can always find the legitimate maintainer(s) on PAUSE under
"View Permissions".};

          $self->index_status($package,
                              $pp->{version},
                              $pp->{infile},
                              PAUSE::mldistwatch::Constants::EMISSPERM,
                              $message,
                              );
          $self->alert(qq{$error:
package[$package]
version[$pp->{version}]
file[$pp->{infile}]
dist[$dist]
userid[$userid]
owners[@owners]
owner[$owner]
});
          return;         # early return
      }

  } else {

      # package has no existence in perms yet, so this guy is OK

      $plan_set_comaint ->("(uploader)");

  }
  $self->verbose(1,sprintf( # just for debugging
                            "02maybe: %-25s %10s %-16s (%s) %s\n",
                            $package,
                            $pp->{version},
                            $pp->{infile},
                            $pp->{filemtime},
                            $dist
                          ));
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
    my $self = shift;

    my $package = $self->{PACKAGE};
    return $package !~ /^\w[\w\:\']*\w?\z/
        || $package !~ /\w\z/
        || $package =~ /:/ && $package !~ /::/
        || $package =~ /\w:\w/
        || $package =~ /:::/;
}

# package PAUSE::package;
sub examine_pkg {
  my $self = shift;

  my $dbh = $self->connect;
  my $package = $self->{PACKAGE};
  my $dist = $self->{DIST};
  my $pp = $self->{PP};
  my $pmfile = $self->{PMFILE};

  # should they be cought earlier? Maybe.
  # but as an ultimate sanity check suggested by Richard Soderberg
  if ($self->_pkg_name_insane) {
      $self->verbose(1,"Package[$package] did not pass the ultimate sanity check");
      delete $self->{FIO};    # circular reference
      return;
  }

  # Query all users with perms for this package

  unless ($self->perm_check){ # (P2.0&P3.0)
      delete $self->{FIO};    # circular reference
      return;
  }

  # Copy permissions from main module to subsidiary modules.
  $self->give_regdowner_perms;

  # Check that package name matches case of file name
  {
    my (undef, $module) = split m{/lib/}, $self->{PMFILE}, 2;
    if ($module) {
      $module = $module =~ s{\.pm\z}{}r =~ s{/}{::}gr;

      if (lc $module eq lc $package && $module ne $package) {
        # warn "/// $self->{PMFILE} vs. $module vs. $package\n";
        $self->add_indexing_warning(
          "Capitalization of package ($package) does not match filename!",
        );
      }
    }
  }

  # Parser problem

  if ($pp->{version} && $pp->{version} =~ /^\{.*\}$/) { # JSON parser error
      my $err = JSON::jsonToObj($pp->{version});
      if ($err->{openerr}) {
          $self->index_status($package,
                              "undef",
                              $pp->{infile},
                              PAUSE::mldistwatch::Constants::EOPENFILE,

                              qq{The PAUSE indexer was not able to
        read the file. It issued the following error: C< $err->{openerr} >},
                              );
      } else {
          $self->index_status($package,
                              "undef",
                              $pp->{infile},
                              PAUSE::mldistwatch::Constants::EPARSEVERSION,

                              qq{The PAUSE indexer was not able to
        parse the following line in that file: C< $err->{line} >

        Note: the indexer is running in a Safe compartement and cannot
        provide the full functionality of perl in the VERSION line. It
        is trying hard, but sometime it fails. As a workaround, please
        consider writing a META.yml that contains a 'provides'
        attribute or contact the CPAN admins to investigate (yet
        another) workaround against "Safe" limitations.)},

                              );
      }
      delete $self->{FIO};    # circular reference
      return;
  }

  # Sanity checks

  for (
        $package,
        $pp->{version},
        $dist
      ) {
      if (!defined || /^\s*$/ || /\s/){  # for whatever reason I come here
          delete $self->{FIO};    # circular reference
          return;            # don't screw up 02packages
      }
  }

  $self->checkin;
  delete $self->{FIO};    # circular reference
}

sub _version_ok {
  my($self, $pp, $package, $dist) = @_;
  if (length $pp->{version} > 16) {
    my $errno = PAUSE::mldistwatch::Constants::ELONGVERSION;
    my $error = PAUSE::mldistwatch::Constants::heading($errno);
    $self->index_status($package,
                        $pp->{version},
                        $pp->{infile},
                        $errno,
                        $error,
                        );
    $self->alert(qq{$error:
package[$package]
version[$pp->{version}]
file[$pp->{infile}]
dist[$dist]
});
    return;
  }
  return 1;
}

# package PAUSE::package;
sub update_package {
  # we come here only for packages that have opack and package

  my $self = shift;
  my $row = shift;

  my $dbh = $self->connect;
  my $package = $self->{PACKAGE};
  my $dist = $self->{DIST};
  my $pp = $self->{PP};
  my $pmfile = $self->{PMFILE};
  my $fio = $self->{FIO};


  my($opack,$oldversion,$odist,$ofilemtime,$ofile) = @$row{
    qw( package version dist filemtime file )
  };

  $self->verbose(1,"Old package data: opack[$opack]oldversion[$oldversion]".
                  "odist[$odist]ofiletime[$ofilemtime]ofile[$ofile]\n");
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

  $self->verbose(1, "New package data: package[$package]infile[$pp->{infile}]".
                  "version[$pp->{version}]".
                  "distorperlok[$distorperlok]oldversion[$oldversion]".
                  "odist[$odist]\n");

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

  if (! $distorperlok) {
  } elsif ($isa_regular_perl) {
      if ($older_isa_regular_perl) {
          if (CPAN::Version->vgt($pp->{version},$oldversion)) {
              $ok++;
          } elsif (CPAN::Version->vgt($oldversion,$pp->{version})) {
          } elsif (CPAN::Version->vcmp($pp->{version},$oldversion)==0
                    &&
                    $tdistmtime >= $odistmtime) {
              $ok++;
          }
      } else {
          if (CPAN::Version->vgt($pp->{version},$oldversion)) {
              $self->index_status($package,
                                  $pp->{version},
                                  $pp->{infile},
                                  PAUSE::mldistwatch::Constants::EDUALOLDER,

                                  qq{Not indexed because package $opack
in file $ofile seems to have a dual life in $odist. Although the other
package is at version [$oldversion], the indexer lets the other dist
continue to be the reference version, shadowing the one in the core.
Maybe harmless, maybe needs resolving.},

                              );
          } else {
              $self->index_status($package,
                                  $pp->{version},
                                  $pp->{infile},
                                  PAUSE::mldistwatch::Constants::EDUALYOUNGER,

                                  qq{Not indexed because package $opack
in file $ofile has a dual life in $odist. The other version is at
$oldversion, so not indexing seems okay.},

                              );
          }
      }
  } elsif (defined $pp->{version} && ! version::is_lax($pp->{version})) {
      $self->index_status($package,
                          $pp->{version},
                          $pmfile,
                          PAUSE::mldistwatch::Constants::EBADVERSION,
                          qq{Not indexed because VERSION [$pp->{version}] is not a valid "lax version" string.},
      );
  } elsif (CPAN::Version->vgt($pp->{version},$oldversion)) {
      # higher VERSION here
      $self->verbose(1, "Package '$package' has newer version ".
                      "[$pp->{version} > $oldversion] $dist wins\n");
      $ok++;
  } elsif (CPAN::Version->vgt($oldversion,$pp->{version})) {
      # lower VERSION number here
      if ($odist ne $dist) {
          $self->index_status($package,
                              $pp->{version},
                              $pmfile,
                              PAUSE::mldistwatch::Constants::EVERFALLING,
                              qq{Not indexed because $ofile in $odist
has a higher version number ($oldversion)},
                              );

          delete $self->dist->{CHECKINS}{ lc $package }{ $package };

          $self->alert(qq{decreasing VERSION number [$pp->{version}]
in package[$package]
dist[$dist]
oldversion[$oldversion]
pmfile[$pmfile]
}); # });
      } elsif ($older_isa_regular_perl) {
          $ok++;          # new on 2002-08-01
      } else {
          # we get a different result now than we got in a previous run
          $self->alert("Taking back previous version calculation. odist[$odist]oversion[$oldversion]dist[$dist]version[$pp->{version}].");
          $ok++;
      }
  } else {

      # 2004-01-04: Stas Bekman asked to change logic here. Up
      # to rev 478 we did not index files with a version of 0
      # and with a falling timestamp. These strange timestamps
      # typically happen for developers who work on more than
      # one computer. Files that are not changed between
      # releases keep two different timestamps from some
      # arbitrary checkout in the past. Stas correctly suggests,
      # we should check these cases for distmtime, not filemtime.

      # so after rev. 478 we deprecate the EMTIMEFALLING constant

      if ($pp->{version} eq "undef"||$pp->{version} == 0) { # no version here,
          if ($tdistmtime >= $odistmtime) { # but younger or same-age dist
              # XXX needs better logging message -- dagolden, 2011-08-13
              $self->verbose(1, "$package noversion comp $dist vs $odist: >=\n");
              $ok++;
          } else {
              $self->index_status(
                                  $package,
                                  $pp->{version},
                                  $pp->{infile},
                                  PAUSE::mldistwatch::Constants::EOLDRELEASE,
                                  qq{Not indexed because $ofile in $odist
also has a zero version number and the distro has a more recent modification time.}
                                  );
          }
      } elsif (CPAN::Version
                ->vcmp($pp->{version},
                      $oldversion)==0) {    # equal version here
          # XXX needs better logging message -- dagolden, 2011-08-13
          $self->verbose(1, "$package version eq comp $dist vs $odist\n");
          if ($tdistmtime >= $odistmtime) { # but younger or same-age dist
              $ok++;
          } else {
              $self->index_status(
                                  $package,
                                  $pp->{version},
                                  $pp->{infile},
                                  PAUSE::mldistwatch::Constants::EOLDRELEASE,
                                  qq{Not indexed because $ofile in $odist
has the same version number and the distro has a more recent modification time.}
                                  );
          }
      } else {
          $self->verbose(1, "Nothing interesting in dist[$dist]package[$package]\n");
      }
  }


  if ($ok) {              # sanity check

      if ($self->{FIO}{DIO}{VERSION_FROM_META_OK}) {
          # nothing to argue at the moment, e.g. lib_pm.PL
      } elsif (
                ! $pp->{simile}
                &&
                (!$fio || $fio->simile($ofile,$package)) # if we have no fio, we can't check simile
              ) {
          $self->verbose(1,
                          "Warning: we ARE NOT simile BUT WE HAVE BEEN ".
                          "simile some time earlier:\n");
          # XXX need a better way to log data -- dagolden, 2011-08-13
          $self->verbose(1,Data::Dumper::Dumper($pp), "\n");
          $ok = 0;
      }
  }

  if ($ok) {
      my $query = qq{SELECT package, version, dist from  packages WHERE LOWER(package) = LOWER(?)};
      my($pkg_recs) = $dbh->selectall_arrayref($query,undef,$package);
      if (@$pkg_recs > 1) {
          my $rec0 = join "|", @{$pkg_recs->[0]};
          my $rec1 = join "|", @{$pkg_recs->[1]};
          $self->index_status
              ($package,
               "undef",
               $pp->{infile},
               PAUSE::mldistwatch::Constants::EDBCONFLICT,
               qq{Indexing failed because of conflicting record for
($rec0) vs ($rec1).
Please report the case to the PAUSE admins at modules\@perl.org.},
              );
          $ok = 0;
      }
  }

  return unless $self->_version_ok($pp, $package, $dist);

  if ($ok) {

      my $query = qq{UPDATE packages SET package = ?, version = ?, dist = ?, file = ?,
filemtime = ?, pause_reg = ? WHERE LOWER(package) = LOWER(?)};
      $self->verbose(1,"Updating package: [$query]$package,$pp->{version},$dist,$pp->{infile},$pp->{filemtime}," . $self->dist->{TIME} . ",$package\n");
      my $rows_affected = eval { $dbh->do
                                     ($query,
                                      undef,
                                      $package,
                                      $pp->{version},
                                      $dist,
                                      $pp->{infile},
                                      $pp->{filemtime},
                                      $self->dist->{TIME},
                                      $package,
                                     );
                             };
      if ($rows_affected) { # expecting only "1" can happen
          $self->index_status
              ($package,
               $pp->{version},
               $pp->{infile},
               PAUSE::mldistwatch::Constants::OK,
               "indexed",
              );
      } else {
          my $dbherrstr = $dbh->errstr;
          $self->index_status
              ($package,
               "undef",
               $pp->{infile},
               PAUSE::mldistwatch::Constants::EDBERR,
               qq{The PAUSE indexer could not store the indexing
result in the DB due the following error: C< $dbherrstr >.
Please report the case to the PAUSE admins at modules\@perl.org.},
              );
      }

  }

}

# package PAUSE::package;
sub index_status {
  my($self) = shift;
  my $dio;
  if (my $fio = $self->{FIO}) {
      $dio = $fio->{DIO};
  } else {
      $dio = $self->{DIO};
  }
  $dio->index_status(@_);
}

sub add_indexing_warning {
  my($self) = shift;
  my $dio;
  if (my $fio = $self->{FIO}) {
      $dio = $fio->{DIO};
  } else {
      $dio = $self->{DIO};
  }
  $dio->add_indexing_warning($self->{PACKAGE}, $_[0]);
}

# package PAUSE::package;
sub insert_into_package {
  my $self = shift;
  my $dbh = $self->connect;
  my $package = $self->{PACKAGE};
  my $dist = $self->{DIST};
  my $pp = $self->{PP};
  my $pmfile = $self->{PMFILE};
  my $distname = CPAN::DistnameInfo->new($dist)->dist;
  my $query = qq{INSERT INTO packages (package, version, dist, file, filemtime, pause_reg, distname) VALUES (?,?,?,?,?,?,?) };
  $self->verbose(1,"Inserting package: [$query] $package,$pp->{version},$dist,$pp->{infile},$pp->{filemtime}," . $self->dist->{TIME} . "\n");

  return unless $self->_version_ok($pp, $package, $dist);
  $dbh->do($query,
            undef,
            $package,
            $pp->{version},
            $dist,
            $pp->{infile},
            $pp->{filemtime},
            $self->dist->{TIME},
            $distname,
          );
  $self->index_status($package,
                      $pp->{version},
                      $pp->{infile},
                      PAUSE::mldistwatch::Constants::OK,
                      "indexed",
                      );
}

# package PAUSE::package;
# returns always the return value of print, so basically always 1
sub checkin_into_primeur {
  my $self = shift;
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
          $self->verbose(1, "x_authority was present but undefined; ignoring!");
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
  my $self = shift;
  my $dbh = $self->connect;
  my $package = $self->{PACKAGE};
  my $dist = $self->{DIST};
  my $pp = $self->{PP};
  my $pmfile = $self->{PMFILE};

  $self->checkin_into_primeur; # called in void context!

  my $row = $dbh->selectrow_hashref(
    qq{
      SELECT package, version, dist, filemtime, file
      FROM packages
      WHERE LOWER(package) = LOWER(?)
    },
    undef,
    $package
  );


  if ($row) {

      # We know this package from some time ago

      $self->update_package($row);

  } else {

      # we hear for the first time about this package

      $self->insert_into_package;

  }

}

1;

