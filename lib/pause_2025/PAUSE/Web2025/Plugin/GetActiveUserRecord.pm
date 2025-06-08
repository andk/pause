package PAUSE::Web2025::Plugin::GetActiveUserRecord;

use Mojo::Base "Mojolicious::Plugin";

sub register {
  my ($self, $app, $conf) = @_;
  $app->helper(active_user_record => \&_get);
}


sub _get {
  my ($c, $hidden_user, $opt) = @_;
  $opt ||= {};
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;

  my $hidden_user_ok = $opt->{hidden_user_ok} // ''; # caller is absolutely
                                                     # sure that hidden_user
                                                     # is authenticated or
                                                     # harmless (mailpw)

  my $req = $c->req;
  if ($hidden_user) {
    Carp::cluck("hidden_user[$hidden_user] passed in as argument with hidden_user_ok[$hidden_user_ok]");
  } else {
    my $hiddenname_para = $req->param('HIDDENNAME') || "";
    $hidden_user ||= $hiddenname_para;
    warn "DEBUG: hidden_user[$hidden_user] after hiddenname parameter[$hiddenname_para]";
  }

  {
    my $uc_hidden_user = uc $hidden_user;
    unless ($uc_hidden_user eq $hidden_user) {
      $c->app->pause->log({level => 'warn', message => "Warning: Had to uc the hidden_user $hidden_user" });
      $hidden_user = $uc_hidden_user;
    }
  }

  my $user = {};
  my $userid = $pause->{User}{userid} // '';
  $mgr->log({level => 'info', message => sprintf("Watch: mgr/User/userid[%s]hidden_user[%s]mgr/UserGroups[%s]caller[%s]where[%s]",
    $userid,
    $hidden_user,
    join(":", keys %{$pause->{UserGroups} || {}}),
    join(":", caller),
    __FILE__.":".__LINE__,
  )});

  if (
    $hidden_user
    &&
    $hidden_user ne $userid
  ){
    # Imagine, MSERGEANT wants to pass Win32::ASP to WNODOM

    my $dbh1 = $mgr->connect;
    my $sth1 = $dbh1->prepare("SELECT * FROM users WHERE userid=?");
    $sth1->execute($hidden_user);
    unless ($sth1->rows){
      Carp::cluck(
                  sprintf(
                          "ALERT: hidden_user[%s] rows_as_s[%s] rows_as_d[%d]",
                          $hidden_user,
                          $sth1->rows,
                          $sth1->rows,
                         ));
      die PAUSE::Web2025::Exception->new(NEEDS_LOGIN => 1);
    }
    my $hiddenuser_h1 = $mgr->fetchrow($sth1, "fetchrow_hashref");

    $sth1->finish;

    # $hiddenuser_h1 should now be WNODOM's record

    if ($opt->{checkonly}) {
      # since we have checkonly this is the MSERGEANT case
      return $hiddenuser_h1;
    } elsif ($hiddenuser_h1->{isa_list}) {

      # This is NOT the MSERGEANT case

      if (
        exists $pause->{IsMailinglistRepresentative}{$hiddenuser_h1->{userid}}
        ||
        (
          $pause->{UserGroups}
          &&
          exists $pause->{UserGroups}{admin}
        )
      ){
        # OK, we believe you come with good intentions, but we check
        # if this action makes sense because we fear for the integrity
        # of the database, no matter if you are user or admin.
        if (
            grep { $_ eq $pause->{Action} } $mgr->config->allow_mlrepr_takeover
           ) {
          warn "Watch: privilege escalation";
          $user = $hiddenuser_h1; # no secrets for a mailinglist
        } else {
          die PAUSE::Web2025::Exception
              ->new(ERROR =>
                    sprintf(
                            qq[Action '%s' seems not to be supported
                            for a mailing list],
                            $pause->{Action},
                           )
                   );
        }
      }
    } elsif (
             $hidden_user_ok
             ||
             $pause->{UserGroups}
             &&
             exists $pause->{UserGroups}{admin}
       ) {

      # This isn't the MSERGEANT case either, must be admin
      # The case of hidden_user_ok is when they forgot password

      my $dbh2 = $mgr->authen_connect;
      my $sth2 = $dbh2->prepare("SELECT secretemail, lastvisit
                                 FROM $PAUSE::Config->{AUTHEN_USER_TABLE}
                                 WHERE $PAUSE::Config->{AUTHEN_USER_FLD}=?");
      $sth2->execute($hidden_user);
      my $hiddenuser_h2 = $mgr->fetchrow($sth2, "fetchrow_hashref");
      $sth2->finish;
      for my $h ($hiddenuser_h1, $hiddenuser_h2) {
        for my $k (keys %$h) {
          $user->{$k} = $h->{$k};
        }
      }
    } elsif (0) {
      return $user;
    } else {
      # So here is the MSERGEANT case, most probably
      # But the ordinary record must do. No secret email stuff here, no passwords
      # 2009-06-15 akoenig : adamk reports a massive security hole
      require YAML::Syck;
      Carp::confess
              (
               YAML::Syck::Dump({ hiddenuser => $hiddenuser_h1,
                                  error => "looks like unwanted privilege escalation",
                                  user => $user,
                                }));
      # maybe we should just return the current user here? or we
      # should check the action? Don't think so, filling HiddenUser
      # member might be OK but returning the other user? Unlikely.
    }
  } else {
    unless ($pause->{User}{fullname}) {
      # this guy most probably came via ABRA and we should fill some slots

      my $dbh1 = $mgr->connect;
      my $sth1 = $dbh1->prepare("SELECT * FROM users WHERE userid=?");
      $sth1->execute($pause->{User}{userid});
      die PAUSE::Web2025::Exception->new(NEEDS_LOGIN => 1) unless $sth1->rows;

      $pause->{User} = $mgr->fetchrow($sth1, "fetchrow_hashref");
      $sth1->finish;

      my $dbh2 = $mgr->authen_connect;
      my $sth2 = $dbh2->prepare("SELECT secretemail
                                 FROM $PAUSE::Config->{AUTHEN_USER_TABLE}
                                 WHERE $PAUSE::Config->{AUTHEN_USER_FLD}=?");
      $sth2->execute($pause->{User}{userid});
      my $row = $mgr->fetchrow($sth2, "fetchrow_hashref");
      $pause->{User}{secretemail} = $row->{secretemail};
      $sth2->finish;
    }
    %$user = (%{$pause->{User}||{}}, %{$pause->{UserSecrets}||{}});
  }
  $pause->{HiddenUser} = $user;
  $user;
}

1;
