package PAUSE::Web::Controller::User::Distperms;

use Mojo::Base "Mojolicious::Controller";

sub peek {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  unless ($req->param("pause99_peek_dist_perms_query")) {
    $req->param("pause99_peek_dist_perms_query" => $pause->{User}{userid});
  }
  unless ($req->param("pause99_peek_dist_perms_by")) {
    $req->param("pause99_peek_dist_perms_by" => "a");
  }

  if (my $qterm = $req->param("pause99_peek_dist_perms_query")) {
    my $by = $req->param("pause99_peek_dist_perms_by");
    my $query = qq{SELECT packages.distname,
                          GROUP_CONCAT(DISTINCT primeur.userid ORDER BY primeur.userid),
                          GROUP_CONCAT(DISTINCT perms.userid ORDER BY perms.userid)
                   FROM packages LEFT JOIN primeur ON primeur.package=packages.package
                                 LEFT JOIN perms ON perms.package=packages.package AND primeur.userid <> perms.userid
                };

    my $db = $mgr->connect;
    my @res;
    my %seen;
    my $where;
    my @bind;
    if ($by =~ /^d/) {
      @bind = ($qterm);
      if ($by eq "de") {
        $where = qq{WHERE packages.distname=? GROUP BY packages.distname};
      } else {
        $where = qq{WHERE packages.distname LIKE ? GROUP BY packages.distname LIMIT 1000};
        # I saw 5.7.3 die with Out Of Memory on the query "%" when no
        # Limit was applied
      }
    } elsif ($by eq "a") {
      @bind = ($qterm, $qterm);
      $where = qq{WHERE primeur.userid=? OR perms.userid=? GROUP BY packages.distname};
    } else {
      die PAUSE::Web::Exception
          ->new(ERROR => "Illegal parameter for pause99_peek_dist_perms_by");
    }
    $query .= $where;
    my $sth = $db->prepare($query);
    $sth->execute(@bind);
    if ($sth->rows > 0) {
      # warn sprintf "query[%s]qterm[%s]rows[%d]", $query, $qterm, $sth->rows;
      while (my @row = $mgr->fetchrow($sth, "fetchrow_array")) {
        if ($seen{$row[0]}++){
          # warn "Ignoring row[$row[0]][$row[1]]";
          next;
        }
        push @res, \@row;
      }
    }
    $sth->finish;
    if (@res) {
      my $dbh = $mgr->connect;
      my @column_names = qw(dist owner comaint);
      my $output_format = $req->param("OF");
      if ($output_format){
        my @hres;
        for my $row (@res) {
          push @hres, { map {$column_names[$_] => $row->[$_] } 0..$#$row };
        }
        if ($output_format eq "YAML") {
          return $c->render_yaml(\@hres);
        } else {
          die "not supported OF=$output_format"
        }
      }
      $pause->{column_names} = \@column_names;

      @res = sort {
        $a->[0] cmp $b->[0]
            ||
        $a->[1] cmp $b->[1]
            ||
        $a->[2] cmp $b->[2]
      } @res;

      $pause->{rows} = \@res;
    }
  }
}

sub move_dist_primary {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  my $u = $c->active_user_record;

  my $db = $mgr->connect;

  my $all_dists = $c->all_pdists($u);

  if (
      $req->param("SUBMIT_pause99_move_dist_primary")
     ) {
    eval {
      my(@seldists, $other_user);
      if (@seldists = @{$req->every_param("pause99_move_dist_primary_d")}
          and
          $other_user = $req->param("pause99_move_dist_primary_a")
         ) {
        $other_user = uc $other_user;
        my $sth1 = $db->prepare("SELECT userid
                                 FROM users
                                 WHERE userid=?");
        $sth1->execute($other_user);
        die PAUSE::Web::Exception
            ->new(ERROR => "$other_user is not a valid userid.")
                unless $sth1->rows;
        local($db->{RaiseError}) = 0;
        my $sth = $db->prepare("UPDATE primeur SET userid=? WHERE package=?");
        my @results;
        for my $seldist (@seldists) {
          die PAUSE::Web::Exception
              ->new(ERROR => "You do not seem to be maintainer of $seldist")
                  unless exists $all_dists->{$seldist};
          my $mods = $db->selectcol_arrayref(
            q{SELECT primeur.package
              FROM primeur JOIN packages ON primeur.package = packages.package
              WHERE packages.distname=? AND primeur.userid=?},
            undef, $seldist, $u->{userid});
          for my $selmod (@$mods) {
            my $ret = $sth->execute($other_user,$selmod);
            my $err = "";
            $err = $db->errstr unless defined $ret;
            $ret ||= "";
            warn "DEBUG: seldist[$seldist]selmod[$selmod]other_user[$other_user]ret[$ret]err[$err]";
            if ($ret) {
              push @results, {
                user => $other_user,
                mod => $selmod,
                dist => $seldist,
              };
            } else {
              push @results, {
                user => $other_user,
                mod => $selmod,
                dist => $seldist,
                error => $err,
              };
            }
          }
        }
        $pause->{results} = \@results;
      }
    };
    if ($@) {
      $pause->{error} = $@->{ERROR};
    }
  }

  $all_dists = $c->all_pdists($u); # again
  my @all_dists = map {[$_, $all_dists->{$_}]} sort keys %$all_dists;
  $pause->{dists} = \@all_dists;

  if (@all_dists == 1) {
    $req->param("pause99_move_dist_primary_d" => $all_dists[0][0]);
  }
}

sub remove_dist_primary {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;

  my $db = $mgr->connect;

  my $all_dists = $c->all_pdists($u);

  if (0) {
    # here I discovered that Apache::Request has case-insensitive keys
    my %p = map { $_, [ $req->every_param($_)] } @{$req->param->names};
    require Data::Dumper; print STDERR "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . Data::Dumper->new([\%p],[qw()])->Indent(1)->Useqq(1)->Dump; # XXX

  }

  if (
      $req->param("SUBMIT_pause99_remove_dist_primary")
     ) {
    eval {
      my(@seldists);
      if (@seldists = @{$req->every_param("pause99_remove_dist_primary_d")}
         ) {
        local($db->{RaiseError}) = 0;
        my $sth = $db->prepare("UPDATE primeur SET userid=? WHERE userid=? AND package=?");

        my @results;
        for my $seldist (@seldists) {
          die PAUSE::Web::Exception
              ->new(ERROR => "You do not seem to be maintainer of $seldist")
                  unless exists $all_dists->{$seldist};
          my $mods = $db->selectcol_arrayref(
            q{SELECT primeur.package
              FROM primeur JOIN packages ON primeur.package = packages.package
              WHERE packages.distname=? AND primeur.userid=?},
            undef, $seldist, $u->{userid});
          for my $selmod (@$mods) {
            my $ret = $sth->execute('ADOPTME',$u->{userid},$selmod);
            my $err = "";
            $err = $db->errstr unless defined $ret;
            $ret ||= "";
            warn "DEBUG: seldist[$seldist]selmod[$selmod]ret[$ret]err[$err]";
            if ($ret) {
              push @results, {
                user => $u->{userid},
                mod => $selmod,
                dist => $seldist,
              };
            } else {
              push @results, {
                user => $u->{userid},
                mod => $selmod,
                dist => $seldist,
                error => $err,
              };
            }
          }
        }
        $pause->{results} = \@results;
      }
    };
  }

  $all_dists = $c->all_pdists($u); # again
  my @all_dists = map {[$_, $all_dists->{$_}]} sort keys %$all_dists;
  $pause->{dists} = \@all_dists;

  if (@all_dists == 1) {
    $req->param("pause99_remove_dist_primary_d" => $all_dists[0][0]);
  }
}

sub make_dist_comaint {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;
  # warn "u->userid[%s]", $u->{userid};

  my $db = $mgr->connect;

  my $all_dists = $c->all_pdists($u);
  # warn sprintf "all_pdists[%s]", join("|", keys %$all_pdists);

  if (
      $req->param("SUBMIT_pause99_make_dist_comaint")
     ) {
    eval {
      my(@seldists,$other_user);
      if (@seldists = @{$req->every_param("pause99_make_dist_comaint_d")}
          and
          $other_user = $req->param("pause99_make_dist_comaint_a")
         ) {
        $other_user = uc $other_user;
        my $sth1 = $db->prepare("SELECT userid
                                 FROM users
                                 WHERE userid=?");
        $sth1->execute($other_user);
        die PAUSE::Web::Exception
            ->new(ERROR => sprintf(
                                   "$other_user is not a valid userid.",
                                  )
                 )
                unless $sth1->rows;
        local($db->{RaiseError}) = 0;
        my $sth = $db->prepare("INSERT INTO perms (package,lc_package,userid)
                            VALUES (?,?,?)");
        my @results;
        for my $seldist (@seldists) {
          die PAUSE::Web::Exception
              ->new(ERROR => "You do not seem to be maintainer of $seldist")
                  unless exists $all_dists->{$seldist};
          my $mods = $db->selectcol_arrayref(
            q{SELECT primeur.package
              FROM primeur JOIN packages ON primeur.package = packages.package
              WHERE packages.distname=? AND primeur.userid=?},
            undef, $seldist, $u->{userid});
          for my $selmod (@$mods) {
            my $ret = $sth->execute($selmod,lc $selmod,$other_user);
            my $err = "";
            $err = $db->errstr unless defined $ret;
            $ret ||= "";
            warn "DEBUG: seldist[$seldist]selmod[$selmod]other_user[$other_user]ret[$ret]err[$err]";
            if ($ret) {
              push @results, {
                user => $other_user,
                mod => $selmod,
                dist => $seldist,
              };
            } elsif ($err =~ /Duplicate entry/) {
              push @results, {
                user => $other_user,
                mod => $selmod,
                dist => $seldist,
                duplicated => 1,
              };
            } else {
              push @results, {
                user => $other_user,
                mod => $selmod,
                dist => $seldist,
                error => $err,
              };
            }
          }
          $pause->{results} = \@results;
        }
      }
    };
    if ($@) {
      $pause->{error} = $@->{ERROR};
    }
  }

  $all_dists = $c->all_pdists($u); # again
  my @all_dists = map {[$_, $all_dists->{$_}]} sort keys %$all_dists;
  $pause->{dists} = \@all_dists;

  if (@all_dists == 1) {
    $req->param("pause99_make_dist_comaint_d" => $all_dists[0][0]);
  }
}

sub remove_dist_comaint {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;

  my $db = $mgr->connect;

  my $all_dists = $c->all_pdists($u);
  my $all_comaints = $c->all_comaints($all_dists,$u);

  if (
      $req->param("SUBMIT_pause99_remove_dist_comaint")
     ) {
    eval {
      my @sel = @{$req->every_param("pause99_remove_dist_comaint_tuples")};
      my $sth1 = $db->prepare("DELETE FROM perms WHERE package=? AND userid=?");
      if (@sel) {
        my @results;
        for my $sel (@sel) {
          my($seldist,$otheruser) = $sel =~ /^(\S+)\s--\s(\S+)$/;
          die PAUSE::Web::Exception
              ->new(ERROR => "You do not seem to be owner of $seldist.")
                  unless exists $all_dists->{$seldist};
          unless (exists $all_comaints->{$sel}) {
            push @results, {
              sel => $sel,
              not_exists => 1,
            };
            next;
          }
          my $mods = $db->selectcol_arrayref(
            q{SELECT primeur.package
              FROM primeur JOIN packages ON primeur.package = packages.package
              WHERE packages.distname=? AND primeur.userid=?},
            undef, $seldist, $u->{userid});
          for my $selmod (@$mods) {
            my $ret = $sth1->execute($selmod,$otheruser);
            my $err = "";
            $err = $db->errstr unless defined $ret;
            $ret ||= "";
            warn "DEBUG: seldist[$seldist]selmod[$selmod]ret[$ret]err[$err]";
            if ($ret) {
              push @results, {
                user => $otheruser,
                mod => $selmod,
                dist => $seldist,
              };
            } else {
              push @results, {
                user => $otheruser,
                mod => $selmod,
                dist => $seldist,
                error => $err,
              };
            }
          }
        }
        $pause->{results} = \@results;
      }
    };
    if ($@) {
      $pause->{error} = $@->{ERROR};
    }
  }

  $all_comaints = $c->all_comaints($all_dists,$u); # again
  my @all = sort keys %$all_comaints;
  $pause->{dists} = \@all;
}

sub giveup_dist_comaint {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;
  my $db = $mgr->connect;

  my $all_dists = $c->all_only_cdists($u);

  if (
      $req->param("SUBMIT_pause99_giveup_dist_comaint")
     ) {
    eval {
      my(@seldists);
      if (@seldists = @{$req->every_param("pause99_giveup_dist_comaint_d")}
         ) {
        local($db->{RaiseError}) = 0;
        my $sth = $db->prepare("DELETE FROM perms WHERE package=? AND userid=?");

        my @results;
        for my $seldist (@seldists) {
          die PAUSE::Web::Exception
              ->new(ERROR => "You do not seem to be co-maintainer of $seldist")
                  unless exists $all_dists->{$seldist};
          my $mods = $db->selectcol_arrayref(
            q{SELECT perms.package
              FROM perms JOIN packages ON perms.package = packages.package
              WHERE packages.distname=? AND perms.userid=?},
            undef, $seldist, $u->{userid});
          for my $selmod (@$mods) {
            my $ret = $sth->execute($selmod,$u->{userid});
            my $err = "";
            $err = $db->errstr unless defined $ret;
            $ret ||= "";
            warn "DEBUG: seldist[$seldist]selmod[$selmod]ret[$ret]err[$err]";
            if ($ret) {
              push @results, {
                user => $u->{userid},
                mod => $selmod,
                dist => $seldist,
              };
              delete $all_dists->{$seldist};
            } else {
              push @results, {
                user => $u->{userid},
                mod => $selmod,
                dist => $seldist,
                error => $err,
              };
            }
          }
        }
        $pause->{results} = \@results;
      }
    };
    if ($@) {
      $pause->{error} = $@->{ERROR};
    }
  }

  $all_dists = $c->all_only_cdists($u); # again
  my @all_dists = map {[$_, $all_dists->{$_}]} sort keys %$all_dists;
  $pause->{dists} = \@all_dists;

  if (@all_dists == 1) {
    $req->param("pause99_giveup_dist_comaint_d" => $all_dists[0][0]);
  }
}

sub all_pdists {
  my ($c, $u) = @_;
  my $mgr = $c->app->pause;
  my $db = $mgr->connect;
  my(%all_dists);
# XXX: This query was too slow under mysql 5.1...
#    qq{SELECT packages.distname, GROUP_CONCAT(DISTINCT p3.userid ORDER BY p3.userid)
#       FROM packages JOIN primeur ON primeur.userid = ? AND primeur.package=packages.package
#       LEFT JOIN packages AS p2 ON packages.distname = p2.distname
#       LEFT JOIN primeur AS p3 ON p2.package = p3.package GROUP BY packages.distname});
  my $sth2 = $db->prepare(
    qq{SELECT packages.distname
       FROM packages JOIN primeur ON primeur.userid = ? AND primeur.package=packages.package});
  $sth2->execute($u->{userid});
  while (my($distname) = $mgr->fetchrow($sth2, "fetchrow_array")) {
    next if $distname eq '';
    my $owners = $db->selectcol_arrayref(
      qq{SELECT DISTINCT(userid) FROM primeur JOIN packages ON packages.distname = ? AND primeur.package = packages.package},
      undef, $distname);
    $all_dists{$distname} = join ',', @$owners;
  }
  $sth2->finish;
  \%all_dists;
}

sub all_cdists {
  my ($c, $u) = @_;
  my $mgr = $c->app->pause;
  my $db = $mgr->connect;
  my(%all_dists);
  my $sth2 = $db->prepare(qq{SELECT packages.distname, GROUP_CONCAT(DISTINCT primeur.userid ORDER BY primeur.userid)
                             FROM packages
                                 JOIN perms ON perms.userid = ? AND perms.package = packages.package
                                 LEFT JOIN primeur ON packages.package = primeur.package
                             GROUP BY packages.distname});
  $sth2->execute($u->{userid});
  while (my($id, $owner) = $mgr->fetchrow($sth2, "fetchrow_array")) {
    $all_dists{$id} = $owner;
  }
  $sth2->finish;
  \%all_dists;
}

sub all_only_cdists {
  my($c,$u) = @_;
  my $all_pdists = $c->all_pdists($u);
  my $all_dists = $c->all_cdists($u);

  for my $k (keys %$all_pdists) {
    delete $all_dists->{$k};
  }
  $all_dists;
}

sub all_comaints {
  my ($c, $all_dists, $u) = @_;
  my $mgr = $c->app->pause;
  my $result = {};
  return $result unless %$all_dists;
  my $db = $mgr->connect;
  my $or = join " OR\n", map { "packages.distname='$_'" } keys %$all_dists;
  my $sth2 = $db->prepare(qq{SELECT packages.distname, userid, perms.package
                             FROM perms LEFT JOIN packages ON perms.package = packages.package
                             WHERE userid <> '$u->{userid}' AND ( $or )
                             });
  $sth2->execute;
  while (my($d,$i,$p) = $mgr->fetchrow($sth2,"fetchrow_array")) {
    $result->{"$d -- $i"}{$p} = undef;
    warn "d[$d]p[$p]i[$i]";
  }
  return $result;
}

1;
