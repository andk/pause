package PAUSE::Web2025::Controller::Root;

use Mojo::Base "Mojolicious::Controller";

sub check {
  my $c = shift;

  if ($c->pause_is_closed) {
    my $user = $c->req->env->{REMOTE_USER};
    if ($user and $user eq "ANDK") {
    } else {
      $c->render("closed");
      return;
    }
  }

  return 1;
}

sub index {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  return unless exists $pause->{User};
  my $u = $c->active_user_record;

  # Special case for cpan-uploaders that post to the /pause/authenquery without any ACTION
  return unless $u->{userid};
  return unless uc $req->method eq 'POST';
  return unless $req->param('SUBMIT_pause99_add_uri_HTTPUPLOAD') || $req->param('SUBMIT_pause99_add_uri_httpupload');

  my $action = 'add_uri';
  $req->param('ACTION' => $action);
  $pause->{Action} = $action;

  # kind of delegate but don't add action to stack
  my $routes = $c->app->routes;
  my $route = $routes->lookup($action) or die "no route for $action";
  my $to = $route->to;
  $routes->_controller($c, $to);
}

sub auth {
  my $c = shift;
  return 1;
}

sub login {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  # already logged in
  if ($pause->{User}{userid}) {
    $c->redirect_to('/');
    return;
  }

  if (uc $req->method eq 'POST') {
    my $user_sent = $req->param('pause_id');
    my $sent_pw   = $req->param('password');

    my $attr = {
      data_source => $PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME},
      username    => $PAUSE::Config->{AUTHEN_DATA_SOURCE_USER},
      password    => $PAUSE::Config->{AUTHEN_DATA_SOURCE_PW},
      pwd_table   => $PAUSE::Config->{AUTHEN_USER_TABLE},
      uid_field   => $PAUSE::Config->{AUTHEN_USER_FLD},
      pwd_field   => $PAUSE::Config->{AUTHEN_PASSWORD_FLD},
    };

    my $dbh;
    warn "DEBUG: attr.data_source[$attr->{data_source}]";
    unless ($dbh = DBI->connect($attr->{data_source},
                                $attr->{username},
                                $attr->{password})) {
      Log::Dispatch::Config->instance->log(level => 'error', message => " db connect error with $attr->{data_source} ");
      return $c->reply->exception(500);
    }

    # generate statement
    my $user_record;
    my @try_user = $user_sent;
    push @try_user, uc $user_sent if $user_sent ne uc $user_sent;
    my %session;

    my $statement = qq{SELECT * FROM $attr->{pwd_table}
                       WHERE $attr->{uid_field}=?};
    # prepare statement
    my $sth;
    unless ($sth = $dbh->prepare($statement)) {
      Log::Dispatch::Config->instance->log(level => 'error', message => "can not prepare statement: $DBI::errstr");
      $sth->finish;
      $dbh->disconnect;
      return $c->reply->exception(500);
    }
    for my $user (@try_user){
      unless ($sth->execute($user)) {
        Log::Dispatch::Config->instance->log(level => 'error', message => " can not execute statement: $DBI::errstr");
        $sth->finish;
        $dbh->disconnect;
        return $c->reply->exception(500);
      }

      if ($sth->rows == 1){
        $user_record = $mgr->fetchrow($sth, "fetchrow_hashref");
        $session{user} = $user;
      }
    }
    $sth->finish;

    # delete not to be carried around
    my $crypt_pw = delete $user_record->{$attr->{pwd_field}};
    if ($crypt_pw) {
      if (PAUSE::Crypt::password_verify($sent_pw, $crypt_pw)) {
        PAUSE::Crypt::maybe_upgrade_stored_hash({
          password => $sent_pw,
          old_hash => $crypt_pw,
          dbh      => $dbh,
          username => $user_record->{user},
        });
        $dbh->do
            ("UPDATE usertable SET lastvisit=NOW() where user=?",
             +{},
             $user_record->{user},
            );
        $dbh->disconnect;
        $c->session(\%session);
        return $c->redirect_to('/');
      } else {
        warn sprintf "failed login: user[%s]uri[%s]auth_required[%d]",
            $user_record->{user}, $req->url->path, 401;
      }
    }
    $dbh->disconnect;
  }
  $pause->{Action} = 'login';
}

1;
