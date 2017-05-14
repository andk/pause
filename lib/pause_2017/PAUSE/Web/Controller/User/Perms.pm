package PAUSE::Web::Controller::User::Perms;

use Mojo::Base "Mojolicious::Controller";

sub peek {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  unless ($req->param("pause99_peek_perms_query")) {
    $req->param("pause99_peek_perms_query" => $pause->{User}{userid});
  }
  unless ($req->param("pause99_peek_perms_by")) {
    $req->param("pause99_peek_perms_by" => "a");
  }

  if (my $qterm = $req->param("pause99_peek_perms_query")) {
    my $by = $req->param("pause99_peek_perms_by");
    my @query = (
                qq{SELECT primeur.package,
                          primeur.userid,
                          "first-come",
                          primeur.userid
                   FROM primeur LEFT JOIN users ON primeur.userid=users.userid
                },
                qq{SELECT perms.package,
                          perms.userid,
                          "co-maint",
                          primeur.userid
                   FROM perms LEFT JOIN users ON perms.userid=users.userid
                              LEFT JOIN primeur ON perms.package=primeur.package
                },
               );

    my $db = $mgr->connect;
    my @res;
    my %seen;
    for my $query (@query) {
      my %fields = (
                    "first-come" => {
                                     package => "primeur.package",
                                     userid  => "primeur.userid",
                                    },
                    "co-maint" => {
                                   package => "perms.package",
                                   userid  => "perms.userid",
                                  }
                   );
      my($qtype) = $query =~ /\"(.+)\"/;
      my($fmap) = $fields{$qtype};
      my $where;
      if ($by =~ /^m/) {
        if ($by eq "me") {
          $where = qq{WHERE $fmap->{package}=?};
        } else {
          $where = qq{WHERE $fmap->{package} LIKE ? LIMIT 1000};
          # I saw 5.7.3 die with Out Of Memory on the query "%" when no
          # Limit was applied
        }
      } elsif ($by eq "a") {
        $where = qq{WHERE $fmap->{userid}=?};
      } else {
        die PAUSE::Web::Exception
            ->new(ERROR => "Illegal parameter for pause99_peek_perms_by");
      }
      $query .= $where;
      my $sth = $db->prepare($query);
      $sth->execute($qterm);
      if ($sth->rows > 0) {
        # warn sprintf "query[%s]qterm[%s]rows[%d]", $query, $qterm, $sth->rows;
        while (my @row = $mgr->fetchrow($sth, "fetchrow_array")) {
          if ($seen{join "|", @row[0,1]}++){
            # warn "Ignoring row[$row[0]][$row[1]]";
            next;
          }
          push @res, \@row;
        }
      }
      $sth->finish;
    }
    if (@res) {
      my $dbh = $mgr->connect;
      for my $row (@res) {
        # add the owner on column 3
        # will already be set except for co-maint modules where the
        # owner is in the modlist but not first-come
        $row->[3] ||= PAUSE::owner_of_module($row->[0], $dbh);
      }
      my @column_names = qw(module userid type owner);
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
            ||
        $a->[3] cmp $b->[3]
      } @res;

      $pause->{rows} = \@res;
    }
  }
}

sub share {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  $c->prefer_post(1); # because the querystring can get too long

  my $subaction = $req->param("SUBACTION");
  unless ($subaction) {
    ####################### 2.1    2.2    3.1    3.2     4.1
  SUBACTION: for my $sa (qw(movepr remopr makeco remocos remome)) {
      if ($req->param("pause99_share_perms_$sa")
          or
          $req->param("SUBMIT_pause99_share_perms_$sa")
          or
          $req->param("weaksubmit_pause99_share_perms_$sa")
         ) {
        $subaction = $sa;
        last SUBACTION;
      }
    }
  }
  $pause->{subaction} = $subaction;
  my $u = $c->active_user_record;

  # warn sprintf "subaction[%s] u->userid[%s]", $subaction||"", $u->{userid}||"";

  unless ($subaction) {
    # NOTE: the 6 submit buttons below are "weak" submit buttons. I
    # want that people first reach the next page with more text and
    # more options.

    my $dbh = $mgr->connect;
    {
      my $sql = qq{SELECT modid
                   FROM mods
                   WHERE userid=?
                   AND mlstatus='list'
                   ORDER BY modid};
      my $sth = $dbh->prepare($sql);
      $sth->execute($u->{userid});
      my @all_mods;
      while (my($id) = $mgr->fetchrow($sth, "fetchrow_array")) {
        # register this mailinglist for the selectbox
        push @all_mods, $id;
      }
      $pause->{mods} = \@all_mods;
    }

    {
      my $all_mods = $c->all_pmods_not_mmods($u);
      my @all_mods = sort keys %$all_mods;
      $pause->{remove_primary} = \@all_mods;
    }

    {
      # it should be sufficiently helpful to prepare only makeco_m on
      # these two submit buttons. For 3.2 people may be a little confused
      # but it is so rarely needed that we do not worry.
      my $all_mods = $c->all_pmods($mgr,$u);
      my @all_mods = sort keys %$all_mods;
      $pause->{make_comaintainer} = \@all_mods;
    }

    {
      my $all_mods = $c->all_only_cmods($mgr,$u);
      my @all_mods = sort keys %$all_mods;
      my %labels;
      my @all_mods_with_label;
      for my $m (@all_mods) {
        # get the owner for modlist modules that don't have first-come
        my $owner = $all_mods->{$m} || PAUSE::owner_of_module($m, $dbh) || '?';
        push @all_mods_with_label, ["$m => $owner", $m];
      }

      $pause->{remove_maintainer} = \@all_mods_with_label;
    }

    return;
  }

  my $method = "_share_$subaction";
  $c->$method;
}

sub _share_movepr {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  my $u = $c->active_user_record;

  my $db = $mgr->connect;

  my $all_mods = $c->all_pmods_not_mmods($u);

  if (
      $req->param("SUBMIT_pause99_share_perms_movepr")
     ) {
    eval {
      my(@selmods, $other_user);
      if (@selmods = $req->param("pause99_share_perms_pr_m")
          and
          $other_user = $req->param("pause99_share_perms_movepr_a")
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
        for my $selmod (@selmods) {
          die PAUSE::Web::Exception
              ->new(ERROR => "You do not seem to be maintainer of $selmod")
                  unless exists $all_mods->{$selmod};
          my $ret = $sth->execute($other_user,$selmod);
          my $err = "";
          $err = $db->errstr unless defined $ret;
          $ret ||= "";
          warn "DEBUG: selmod[$selmod]other_user[$other_user]ret[$ret]err[$err]";
          if ($ret) {
            push @results, {
              user => $other_user,
              mod => $selmod,
            };
          } else {
            push @results, {
              user => $other_user,
              mod => $selmod,
              error => $err,
            };
          }
        }
        $pause->{results} = \@results;
      }
    };
    if ($@) {
      $pause->{error} = $@->{ERROR};
    }
  }

  my @all_mods = sort keys %$all_mods;
  $pause->{mods} = \@all_mods;

  if (@all_mods == 1) {
    $req->param("pause99_share_perms_pr_m" => $all_mods[0]);
  }
}

sub _share_remopr {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;

  my $db = $mgr->connect;

  my $all_mods = $c->all_pmods_not_mmods($u);

  if (0) {
    # here I discovered that Apache::Request has case-insensitive keys
    my %p = map { $_, [ $req->param($_)] } $req->param;
    require Data::Dumper; print STDERR "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . Data::Dumper->new([\%p],[qw()])->Indent(1)->Useqq(1)->Dump; # XXX

  }

  if (
      $req->param("SUBMIT_pause99_share_perms_remopr")
     ) {
    eval {
      my(@selmods);
      if (@selmods = $req->param("pause99_share_perms_pr_m")
         ) {
        local($db->{RaiseError}) = 0;
        my $sth = $db->prepare("DELETE FROM primeur WHERE userid=? AND package=?");

        my @results;
        for my $selmod (@selmods) {
          die PAUSE::Web::Exception
              ->new(ERROR => "You do not seem to be maintainer of $selmod")
                  unless exists $all_mods->{$selmod};
          my $ret = $sth->execute($u->{userid},$selmod);
          my $err = "";
          $err = $db->errstr unless defined $ret;
          $ret ||= "";
          warn "DEBUG: selmod[$selmod]ret[$ret]err[$err]";
          if ($ret) {
            push @results, {
              user => $u->{userid},
              mod => $selmod,
            };
          } else {
            push @results, {
              user => $u->{userid},
              mod => $selmod,
              error => $err,
            };
          }
        }
      }
    };
  }

  my @all_mods = sort keys %$all_mods;
  $pause->{mods} = \@all_mods;

  if (@all_mods == 1) {
    $req->param("pause99_share_perms_pr_m" => $all_mods[0]);
  }
}

sub _share_makeco {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;
  # warn "u->userid[%s]", $u->{userid};

  my $db = $mgr->connect;

  my $all_mmods = $c->all_mmods($u);
  # warn sprintf "all_mmods[%s]", join("|", keys %$all_mmods);
  my $all_pmods = $c->all_pmods($u);
  # warn sprintf "all_pmods[%s]", join("|", keys %$all_pmods);
  my $all_mods = {%$all_mmods, %$all_pmods};

  if (
      $req->param("SUBMIT_pause99_share_perms_makeco")
     ) {
    eval {
      my(@selmods,$other_user);
      if (@selmods = $req->param("pause99_share_perms_makeco_m")
          and
          $other_user = $req->param("pause99_share_perms_makeco_a")
         ) {
        $other_user = uc $other_user;
        my $sth1 = $db->prepare("SELECT userid
                                 FROM users
                                 WHERE userid=?");
        $sth1->execute($other_user);
        die PAUSE::Web::Exception
            ->new(ERROR => sprintf(
                                   "%s is not a valid userid.",
                                   $mgr->escapeHTML($other_user),
                                  )
                 )
                unless $sth1->rows;
        local($db->{RaiseError}) = 0;
        my $sth = $db->prepare("INSERT INTO perms (package,userid)
                            VALUES (?,?)");

        my @results;
        for my $selmod (@selmods) {
          die PAUSE::Web::Exception
              ->new(ERROR => "You do not seem to be maintainer of $selmod")
                  unless exists $all_mods->{$selmod};
          my $ret = $sth->execute($selmod,$other_user);
          my $err = "";
          $err = $db->errstr unless defined $ret;
          $ret ||= "";
          warn "DEBUG: selmod[$selmod]other_user[$other_user]ret[$ret]err[$err]";
          if ($ret) {
            push @results, {
              user => $other_user,
              mod => $selmod,
            };
          } elsif ($err =~ /Duplicate entry/) {
            push @results, {
              user => $other_user,
              mod => $selmod,
              duplicated => 1,
            };
          } else {
            push @results, {
              user => $other_user,
              mod => $selmod,
              error => $err,
            };
          }
          $pause->{results} = \@results;
        }
      }
    };
    if ($@) {
      $pause->{error} = $@->{ERROR};
    }
  }

  my @all_mods = sort keys %$all_mods;
  $pause->{mods} = \@all_mods;

  if (@all_mods == 1) {
    $req->param("pause99_share_perms_makeco_m" => $all_mods[0]);
  }
}

sub _share_remocos {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;

  my $db = $mgr->connect;

  my $all_mmods = $c->all_mmods($u);
  my $all_pmods = $c->all_pmods($u);
  my $all_mods = { %$all_mmods, %$all_pmods, $u };
  my $all_comaints = $c->all_comaints($all_mods,$u);

  if (
      $req->param("SUBMIT_pause99_share_perms_remocos")
     ) {
    eval {
      my @sel = $req->param("pause99_share_perms_remocos_tuples");
      my $sth1 = $db->prepare("DELETE FROM perms WHERE package=? AND userid=?");
      if (@sel) {
        my @results;
        for my $sel (@sel) {
          my($selmod,$otheruser) = $sel =~ /^(\S+)\s--\s(\S+)$/;
          die PAUSE::Web::Exception
              ->new(ERROR => "You do not seem to be owner of $selmod")
                  unless exists $all_mods->{$selmod};
          unless (exists $all_comaints->{$sel}) {
            push @results, {
              mod => $sel,
              not_exists => 1,
            };
            next;
          }
          my $ret = $sth1->execute($selmod,$otheruser);
          my $err = "";
          $err = $db->errstr unless defined $ret;
          $ret ||= "";
          warn "DEBUG: selmod[$selmod]ret[$ret]err[$err]";
          if ($ret) {
            push @results, {
              user => $otheruser,
              mod => $selmod,
            };
          } else {
            push @results, {
              user => $otheruser,
              mod => $selmod,
              error => $err,
            };
          }
        }
        $pause->{results} = \@results;
      }
    };
    if ($@) {
      $pause->{error} = $@->{ERROR};
    }
  }

  my @all = sort keys %$all_comaints;
  $pause->{mods} = \@all;
}

sub _share_remome {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;
  my $db = $mgr->connect;

  my $all_mods = $c->all_only_cmods($u);

  if (
      $req->param("SUBMIT_pause99_share_perms_remome")
     ) {
    eval {
      my(@selmods);
      if (@selmods = $req->param("pause99_share_perms_remome_m")
         ) {
        local($db->{RaiseError}) = 0;
        my $sth = $db->prepare("DELETE FROM perms WHERE package=? AND userid=?");

        my @results;
        for my $selmod (@selmods) {
          die PAUSE::Web::Exception
              ->new(ERROR => "You do not seem to be co-maintainer of $selmod")
                  unless exists $all_mods->{$selmod};
          my $ret = $sth->execute($selmod,$u->{userid});
          my $err = "";
          $err = $db->errstr unless defined $ret;
          $ret ||= "";
          warn "DEBUG: selmod[$selmod]ret[$ret]err[$err]";
          if ($ret) {
            push @results, {
              user => $u->{userid},
              mod => $selmod,
            };
            delete $all_mods->{$selmod};
          } else {
            push @results, {
              user => $u->{userid},
              mod => $selmod,
              error => $err,
            };
          }
        }
        $pause->{results} = \@results;
      }
    };
    if ($@) {
      $pause->{error} = $@->{ERROR};
    }
  }

  my @all_mods = sort keys %$all_mods;
  $pause->{mods} = \@all_mods;

  if (@all_mods == 1) {
    $req->param("pause99_share_perms_remome_m" => $all_mods[0]);
  }
}

sub all_pmods_not_mmods {
  my ($c, $u) = @_;
  my $mgr = $c->app->pause;
  my $db = $mgr->connect;
  my(%all_mods);
  my $sth2 = $db->prepare(qq{SELECT package
                             FROM primeur
                             WHERE userid=?});
  $sth2->execute($u->{userid});
  while (my($id) = $mgr->fetchrow($sth2, "fetchrow_array")) {
    $all_mods{$id} = undef;
  }
  $sth2->finish;
  $sth2 = $db->prepare(qq{SELECT modid
                             FROM mods
                             WHERE userid=?
                             AND mlstatus='list'
  });
  $sth2->execute($u->{userid});
  while (my($id) = $mgr->fetchrow($sth2, "fetchrow_array")) {
    delete $all_mods{$id};
  }
  $sth2->finish;
  \%all_mods;
}

sub all_cmods {
  my ($c, $u) = @_;
  my $mgr = $c->app->pause;
  my $db = $mgr->connect;
  my(%all_mods);
  my $sth2 = $db->prepare(qq{SELECT perms.package, primeur.userid
                             FROM perms LEFT JOIN primeur
                               ON perms.package = primeur.package
                             WHERE perms.userid=?});
  $sth2->execute($u->{userid});
  while (my($id, $owner) = $mgr->fetchrow($sth2, "fetchrow_array")) {
    $all_mods{$id} = $owner;
  }
  $sth2->finish;
  \%all_mods;
}

sub all_pmods {
  my ($c, $u) = @_;
  my $mgr = $c->app->pause;
  my $db = $mgr->connect;
  my(%all_mods);
  my $sth2 = $db->prepare(qq{SELECT package
                             FROM primeur
                             WHERE userid=?});
  $sth2->execute($u->{userid});
  while (my($id) = $mgr->fetchrow($sth2, "fetchrow_array")) {
    $all_mods{$id} = undef;
  }
  $sth2->finish;
  \%all_mods;
}

sub all_mmods {
  my ($c, $u) = @_;
  my $mgr = $c->app->pause;
  my $db = $mgr->connect;
  my(%all_mods);
  my $sth2 = $db->prepare(qq{SELECT modid
                             FROM mods
                             WHERE userid=?});
  $sth2->execute($u->{userid});
  while (my($id) = $mgr->fetchrow($sth2, "fetchrow_array")) {
    $all_mods{$id} = undef;
  }
  $sth2->finish;
  \%all_mods;
}

sub all_only_cmods {
  my($c,$u) = @_;
  my $all_mmods = $c->all_mmods($u);
  my $all_pmods = $c->all_pmods($u);
  my $all_mods = $c->all_cmods($u);

  for my $k (keys %$all_mmods) {
    delete $all_mods->{$k};
  }
  for my $k (keys %$all_pmods) {
    delete $all_mods->{$k};
  }
  $all_mods;
}

sub all_comaints {
  my ($c, $all_mods, $u) = @_;
  my $mgr = $c->app->pause;
  my $result = {};
  my $db = $mgr->connect;
  my $or = join " OR\n", map { "package='$_'" } keys %$all_mods;
  my $sth2 = $db->prepare(qq{SELECT package, userid
                             FROM perms
                             WHERE userid <> '$u->{userid}' AND ( $or )});
  $sth2->execute;
  while (my($p,$i) = $mgr->fetchrow($sth2,"fetchrow_array")) {
    $result->{"$p -- $i"} = undef;
    warn "p[$p]i[$i]";
  }
  return $result;
}

1;
