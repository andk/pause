package PAUSE::Web::Controller::User;

use Mojo::Base "Mojolicious::Controller";
use File::pushd;
use PAUSE ();
use Set::Crontab;

sub edit_uris {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  my $selectedid = "";
  my $selectedrec = {};
  if (my $param = $req->param("pause99_edit_uris_3")) { # upper selectbox
    $selectedid = $param;
  }
  my $u = $c->active_user_record;

  my $dbh = $mgr->connect;
  my $sql = qq{SELECT uriid
               FROM uris
               WHERE dgot=''
                 AND userid=?
               ORDER BY uriid};
  my $sth = $dbh->prepare($sql);
  $sth->execute($u->{userid});

  my @all_recs;
  my %labels;
  if (my $rows = $sth->rows) {
    my $sth2 = $dbh->prepare(qq{SELECT *
                                FROM uris
                                WHERE dgot=''
                                  AND dverified=''
                                  AND uriid=?
                                  AND userid=?});
    while (my($id) = $mgr->fetchrow($sth, "fetchrow_array")) {
      # register this mailinglist for the selectbox
      push @all_recs, $id;
      # query for more info about it
      $sth2->execute($id,$u->{userid}); # really needed only for the
                                        # record we want to edit, but
                                        # maybe also needed for a
                                        # label in the selectbox
      my($rec) = $mgr->fetchrow($sth2, "fetchrow_hashref");
      # we will display the name along the ID
      # $labels{$id} = "$id ($rec->{userid})";
      $labels{$id} = $id; # redundant, but flexible
      if ($rows == 1 || $id eq $selectedid) {
        # if this is the selected one, we just store it immediately
        $selectedid = $id;
        $selectedrec = $rec;
      }
    }
  } else {
    $pause->{no_pending_uploads} = 1;
    return;
  }

  $pause->{all_recs} = [map {[$labels{$_} => $_]} @all_recs];
  $pause->{selected} = $selectedrec;

  if ($selectedid) {
    my @m_rec;
    my $force_sel = $req->param('pause99_edit_uris_2');
    my $update_sel = $req->param('pause99_edit_uris_4');
    $pause->{update_sel} = $update_sel;

    my $saw_a_change;
    my $now = time;

    for my $field (qw(
      uri
      nosuccesstime
      nosuccesscount
      changed
      changedby
    )) {
      my $fieldname = "pause99_edit_uris_$field";
      if ($force_sel) {
        $req->param($fieldname, $selectedrec->{$field}||"");
      } elsif ($update_sel && $field eq "uri") {
        my $param = $req->param($fieldname);
        if ($param ne $selectedrec->{$field}) {
          # no, we do not double check for user here. What if they
          # change the owner? And we do not prepare outside the loop
          # because the is a $fields in there
          my $sql = qq{UPDATE uris
                       SET $field=?,
                           changed=?,
                           changedby=?
                       WHERE uriid=?};

          my $usth = $dbh->prepare($sql);
          my $ret = $usth->execute($param,
                                   $now,
                                   $u->{userid},
                                   $selectedrec->{uriid});

          $saw_a_change = 1 if $ret > 0;
          $usth->finish;
        }
      }
    }

    if ($saw_a_change) {
      $pause->{changed} = 1;

      my $mailbody = $c->render_to_string("email/user/edit_uris", format => "email");
      my @to = $mgr->prepare_sendto($u, $pause->{User}, $mgr->config->mailto_admins);
      my $header = {
                    Subject => "Uri update for $selectedrec->{uriid}"
                   };
      $mgr->send_mail_multi(\@to,$header,$mailbody);
    }
  }
}

sub reindex {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  my $u = $c->active_user_record;
  my $dbh = $mgr->connect;
  local($dbh->{RaiseError}) = 0;
  my $userhome = PAUSE::user2dir($u->{userid});
  $pause->{userhome} = $userhome;

  my $pushd = eval { pushd("$PAUSE::Config->{MLROOT}/$userhome") } or return;

  my $blurb = "";
  my $server = $PAUSE::Config->{SERVER_NAME} || $req->url->to_abs->host;
  if ($req->param('SUBMIT_pause99_reindex_delete')) {

    my $sql = "DELETE FROM distmtimes
               WHERE dist = ?";
    my $sth = $dbh->prepare($sql);
    foreach my $f (@{$req->every_param('pause99_reindex_FILE')}) {
      if ($f =~ m,^/, || $f =~ m,/\.\./,) {
        $blurb .= "WARNING: illegal filename: $userhome/$f\n";
        next;
      }
      unless (-f $f){
        $blurb .= "WARNING: file not found: $userhome/$f\n";
        next;
      }
      if ($f =~ m{ (^|/) CHECKSUMS }x) {
        $blurb .= "WARNING: indexing CHECKSUMS considered unnecessary: $userhome/$f\n";
        next;
      }
      # delete from distmtimes where distmtimes.dist like '%SREZIC%Tk-DateE%';
      my $ret = $sth->execute("$userhome/$f");
      if ($ret > 0) {
        $blurb .= "\$CPAN/authors/id/$userhome/$f\n";
      } else {
        $blurb .= "WARNING: $userhome/$f has never been indexed.\n"
               .  "(Maybe it's not a stable release and will not get (re)indexed.)\n";
        next;
      }
    }
  }
  if ($blurb) {
    my $eta;
    {
      my $ctf = "$PAUSE::Config->{CRONPATH}/CRONTAB.ROOT"; # crontabfile
      unless (-f $ctf) {
        $ctf = "/tmp/crontab.root";
      }
      if (-f $ctf) {
        open my $fh, "<", $ctf or die "XXX";
        local $/ = "\n";
        my $minute;
        while (<$fh>) {
          s/\#.*//;
          next unless /mldistwatch/;
          ($minute) = split " ", $_, 2;
          last;
        }
        my $sc;
        eval { $sc = Set::Crontab->new($minute,[0..59]); };
        if ($@) {
          warn "Could not create a Crontab object: $@ (minute[$minute])";
          $eta = "N/A";
        } else {
          my $now = time;
          $now -= $now%60;
          for (my $i = 1; $i<=60; $i++) {
            my $fut = $now + $i * 60;
            my $fum = int $fut % 3600 / 60;
            next unless $sc->contains($fum);
            $eta = gmtime( $fut + $PAUSE::Config->{RUNTIME_MLDISTWATCH} ) . " UTC";
            last;
          }
        }
      } else {
        warn "Not found: $ctf";
        $eta = "N/A";
      }
    }
    $pause->{blurb} = $blurb;
    $pause->{eta} = $eta;

    my @to = $mgr->prepare_sendto($u, $pause->{User}, $PAUSE::Config->{ADMIN});
    my $mailbody = $c->render_to_string("email/user/reindex", format => "email");
    my $header = {
                  Subject => "Scheduled for reindexing $u->{userid}"
                 };
    $mgr->send_mail_multi(\@to, $header, $mailbody);

    $pause->{mailbody} = $mailbody;
  }

  my %files = $c->manifind;

  foreach my $f (keys %files) {
    if (
        $f =~ /\.(?:readme|meta)$/ ||
        $f eq "CHECKSUMS"
       ) {
      delete $files{$f};
      next;
    }
  }
  $pause->{files} = \%files;
}

sub reset_version {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;

  my $dbh = $mgr->connect;
  local($dbh->{RaiseError}) = 0;

  my $blurb = "";
  my($usersubstr) = sprintf("%s/%s/%s/",
                            substr($u->{userid},0,1),
                            substr($u->{userid},0,2),
                            $u->{userid},
                           );
  my($usersubstrlen) = length $usersubstr;

  my $sqls = "SELECT package, version, dist FROM packages
             WHERE substring(dist,1,$usersubstrlen) = ?";
  my $sths = $dbh->prepare($sqls);
  if ($req->param('SUBMIT_pause99_reset_version_forget')) {
    my $sqls2 = "SELECT version FROM packages
                WHERE package = ? AND substring(dist,1,$usersubstrlen) = ?";
    my $sths2 = $dbh->prepare($sqls2);
    my $sqlu = "UPDATE packages
               SET version='undef'
               WHERE package = ? AND substring(dist,1,$usersubstrlen) = ?";
    my $sthu = $dbh->prepare($sqlu);
  PKG: foreach my $f (@{$req->every_param('pause99_reset_version_PKG')}) {
      $sths2->execute($f,$usersubstr);
      my($version) = $sths2->fetchrow_array;
      next PKG if $version eq 'undef';
      my $ret = $sthu->execute($f,$usersubstr);
      $blurb .= sprintf(
                        "%s: %s '%s' => 'undef'\n",
                        $ret==0 ? "Not reset" : "Reset",
                        $f,
                        $version,
                       );
    }
  }

  if ($blurb) {
    $pause->{blurb} = $blurb;

    my @to = $mgr->prepare_sendto($u, $pause->{User}, $PAUSE::Config->{ADMIN});
    my $mailbody = $c->render_to_string("email/user/reset_version", format => "email");
    my $header = {
                  Subject => "Version reset for $u->{userid}"
                 };
    $mgr->send_mail_multi(\@to, $header, $mailbody);

    $pause->{mailbody} = $mailbody;
  }
  $sths->execute($usersubstr);
  if ($sths->rows == 0) {
    return;
  }

  my %packages;
  while (my($package, $version, $dist) = $sths->fetchrow_array) {
    $packages{$package} = {version => $version, dist => $dist};
  }
  $pause->{packages} = \%packages;
}

sub tail_logfile {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $req = $c->req;

  my $tail = $req->param("pause99_tail_logfile_1") || 5000;
  my $file = $PAUSE::Config->{PAUSE_LOG};
  if ($PAUSE::Config->{TESTHOST}) {
    $file = "/usr/local/apache/logs/error_log"; # for testing
  }
  open my $fh, "<", $file or die "Could not open $file: $!";
  seek $fh, -$tail, 2;
  local($/);
  $/ = "\n";
  <$fh>;
  $/ = undef;

  $pause->{tail} = <$fh>;
}

sub change_passwd {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  my $u = eval { $c->active_user_record };
  die PAUSE::Web::Exception->new(ERROR => "User not found", HTTP_STATUS => 401) if $@;

  if (uc $req->method eq 'POST' and $req->param("pause99_change_passwd_sub")) {
    if (my $pw1 = $req->param("pause99_change_passwd_pw1")) {
      if (my $pw2 = $req->param("pause99_change_passwd_pw2")) {
        if ($pw1 eq $pw2) {
          # create a new crypted password, store it, report
          my $pwenc = PAUSE::Crypt::hash_password($pw1);
          my $dbh = $mgr->authen_connect;
          my $sql = qq{UPDATE $PAUSE::Config->{AUTHEN_USER_TABLE}
                       SET $PAUSE::Config->{AUTHEN_PASSWORD_FLD} = ?,
                           forcechange = ?,
                           changed = ?,
                           changedby = ?
                       WHERE $PAUSE::Config->{AUTHEN_USER_FLD} = ?};
          # warn "sql[$sql]";
          my $rc = $dbh->do($sql,undef,
                            $pwenc,0,time,$pause->{User}{userid},$u->{userid});
          warn "rc[$rc]";
          die PAUSE::Web::Exception
              ->new(ERROR =>
                    sprintf qq[Could not set password: '%s'], $dbh->errstr
                   ) unless $rc;
          if ($rc == 0) {
            $sql = qq{INSERT INTO $PAUSE::Config->{AUTHEN_USER_TABLE}
                       ($PAUSE::Config->{AUTHEN_USER_FLD},
                           $PAUSE::Config->{AUTHEN_PASSWORD_FLD},
                               forcechange,
                                   changed,
                                       changedby ) VALUES
                       (?, ?,  ?,  ?,  ?)
            };
            $rc = $dbh->do($sql,undef,
                           $u->{userid},
                           $pwenc,
                           0,
                           time,
                           $pause->{User}{userid},
                           $u->{userid}
                          );
            die PAUSE::Web::Exception
                ->new(ERROR =>
                      sprintf qq[Could not insert user record: '%s'], $dbh->errstr
                     ) unless $rc;
          }
          for my $anon ($pause->{User}, $u) {
            die PAUSE::Web::Exception
                ->new(ERROR => "Panic: unknown user") unless $anon->{userid};
            next if $anon->{fullname};
            $mgr->log({level => 'error', message => "Unknown fullname for $anon->{userid}!" });
          }
          $pause->{password_stored} = 1;

          my @to = $mgr->prepare_sendto($u, $pause->{User});
          my $header = {Subject => "Password Update"};
          my $mailbody = $c->render_to_string("email/user/change_passwd", format => "email");
          $mgr->send_mail_multi(\@to, $header, $mailbody);

          # Remove used token
          $sql = qq{DELETE FROM abrakadabra WHERE user = ?};
          $rc = $dbh->do($sql, undef, $u->{userid});
          die PAUSE::Web::Exception
              ->new(ERROR =>
                    sprintf qq[Could not delete token: '%s'], $dbh->errstr
                   ) unless $rc;
          $mgr->log({level => 'info', message => "Removed used token for $u->{userid}" });
        } else {
          die PAUSE::Web::Exception
              ->new(ERROR => "The two passwords didn't match.");
        }
      } else {
        die PAUSE::Web::Exception
            ->new(ERROR => "You need to fill in the same password in both fields.");
      }
    } else {
      die PAUSE::Web::Exception
          ->new(ERROR => "Please fill in the form with passwords.");
    }
  }
}

sub pause_logout {
  my $c = shift;
  $c->serve_pause_doc("logout.html", \&_fix_logout);
}

sub _fix_logout {
  my $html = shift;
  my $rand = rand 1;
  # the redirect solutions fail miserably the second time when tried
  # with the exact same querystring again.
  $html =~ s/__RANDOMSTRING__/$rand/g;
  $html;
}

1;
