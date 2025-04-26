package PAUSE::Web2025::Plugin::ConfigPerRequest;

# XXX: Some of these can be moved into root#check etc,
# and some can be removed now

use Mojo::Base "Mojolicious::Plugin";
use Sys::Hostname;

sub register {
  my ($self, $app, $conf) = @_;
  $app->hook(before_dispatch => \&_before_dispatch);
  $app->helper(need_form_data => \&_need_form_data);
  $app->helper(is_allowed_action => \&_is_allowed_action);
}

sub _before_dispatch {
  my $c = shift;

  $c->stash(".pause" => {}) unless $c->stash(".pause");

  $c->stash(".pause")->{Action} = $c->req->param('ACTION');

  _is_ssl($c);
  _retrieve_user($c);
  _set_allowed_actions($c);
}

sub _is_ssl {
  my $c = shift;
  my $pause = $c->stash(".pause");
  if ($c->req->url->to_abs->scheme eq "https") {
    $pause->{is_ssl} = 1;
  } elsif ($PAUSE::Config->{TRUST_IS_SSL_HEADER}) {
    my $header = $c->req->headers->header("X-pause-is-SSL") || 0;
    $pause->{is_ssl} = !!$header;
  }
}

sub _need_form_data {
  my $c = shift;
  my $pause = $c->stash(".pause");
  if (@_) {
    $pause->{need_form_data} = shift;
  }
  $pause->{need_form_data};
}


sub _retrieve_user {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $session = $c->session || {};

  my $user = $session->{user} or return;

  # This is a database application with nearly all users having write access
  # Write access means expiration any moment
  my $headers = $c->res->headers;
  $headers->header('Pragma', 'no-cache');
  $headers->header('Cache-control', 'no-cache');
  # XXX: $res->no_cache(1);
  # This is annoying when we ask for the who-is-who list and it
  # hasn't changed since the last time, but for most cases it's
  # safer to expire

  # we are not authenticating here, we retrieve the user record from
  # the open database. Thus
  my $dbh = $mgr->connect; # and not authentication database
  local($dbh->{RaiseError}) = 0;
  my($sql, $sth);
  $sql = qq{SELECT *
            FROM users
            WHERE userid=? AND ustatus != 'nologin'};
  $sth = $dbh->prepare($sql);
  if ($sth->execute($user)) {
    if (0 == $sth->rows) {
      my($sql7,$sth7);
      $sql7 = qq{SELECT *
                 FROM users
                 WHERE userid=?};
      $sth7 = $dbh->prepare($sql7);
      $sth7->execute($user);
      my $error;
      if ($sth7->rows > 0) {
        $error = "User '$user' set to nologin. Many users with an insecure password have got their password reset recently because of an incident on perlmonks.org. Please talk to modules\@perl.org to find out how to proceed";
      } else {
        $error = "User '$user' not known";
      }
      die PAUSE::Web2025::Exception->new(ERROR => $error);
    } else {
      $pause->{User} = $mgr->fetchrow($sth, "fetchrow_hashref");
    }
  } else {
    die PAUSE::Web2025::Exception->new(ERROR => $dbh->errstr);
  }
  $sth->finish;

  my $dbh2 = $mgr->authen_connect;
  $sth = $dbh2->prepare("SELECT *
                         FROM $PAUSE::Config->{AUTHEN_USER_TABLE}
                         WHERE $PAUSE::Config->{AUTHEN_USER_FLD}=?");
  $sth->execute($user);
  my $user_record = $sth->fetchrow_hashref;
  delete $user_record->{$PAUSE::Config->{AUTHEN_PASSWORD_FLD}};
  $pause->{User}{secretemail}  = $user_record->{secretemail};
  $sth->finish;

  $sql = qq{SELECT *
            FROM grouptable
            WHERE user=?};
  $sth = $dbh2->prepare($sql);
  if ($sth->execute($user)) {
    $pause->{UserGroups} = {};
    while (my $rec = $mgr->fetchrow($sth, "fetchrow_hashref")) {
      $pause->{UserGroups}{$rec->{ugroup}} = undef;
    }
  } else {
    die PAUSE::Web2025::Exception->new(ERROR => $dbh2->errstr);
  }
  $sth->finish;

  delete $pause->{UserGroups}{mlrepr}; # virtual group, disallow in the table
  $sql = qq{SELECT *
            FROM list2user
            WHERE userid=?};
  $sth = $dbh->prepare($sql);
  $sth->execute($user) or die PAUSE::Web2025::Exception->new(ERROR => $dbh->errstr);
  if ($sth->rows > 0) {
    $pause->{UserGroups}{mlrepr} = undef; # is a virtual group
    my %mlrepr;
    while (my $rec = $mgr->fetchrow($sth, "fetchrow_hashref")) {
      $mlrepr{$rec->{maillistid}} = undef;
    }
    $pause->{IsMailinglistRepresentative} = \%mlrepr;
  }

  $pause->{UserSecrets} = $user_record;
  if ( $pause->{UserSecrets}{forcechange} ) {
    $pause->{Action} = "change_passwd"; # ueberschreiben
    $c->req->param(ACTION => "change_passwd"); # faelschen
  }
}


sub _set_allowed_actions {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  my ($param, @allow_submit, %allow_action);

  # What is allowed here is allowed to anybody
  @allow_action{ $mgr->config->action_names_for('public') } = ();

  @allow_submit = (
                   "request_id",
                  );

  my $userid = '';
  if ($pause->{User} && $pause->{User}{userid} && $pause->{User}{userid} ne "-") {
    $userid = $pause->{User}{userid};

    # warn "userid[$pause->{User}{userid}]";

    # All authenticated Users
    for my $command ( $mgr->config->action_names_for('user') ) {
      $allow_action{$command} = undef;
      push @allow_submit, $command;
    }

    # Only Mailinglist Representatives
    if (exists $pause->{UserGroups}{mlrepr} or exists $pause->{UserGroups}{admin}) {
      for my $command ( $mgr->config->action_names_for('mlrepr') ) {
        $allow_action{$command} = undef;
        push @allow_submit, $command;
      }
    }

    # Postmaster or admin
    if (
        exists $pause->{UserGroups}{admin}
        or
        exists $pause->{UserGroups}{postmaster}
       ) {
      for my $command (
                       "email_for_admin",
                      ) {
        $allow_action{$command} = undef;
        push @allow_submit, $command;
      }
    }

    # Only Admins
    if (exists $pause->{UserGroups}{admin}) {
      # warn "We have an admin here";
      for my $command ( $mgr->config->action_names_for('admin') ) {
        $allow_action{$command} = undef;
        push @allow_submit, $command;
      }
    }

  } elsif ($param = $req->param("ABRA")) {

    # TUT: if they sent ABRA, the only thing we let them do is change
    # their password. The parameter consists of username-dot-token.
    my($user, $passwd) = $param =~ m|(.*?)\.(.*)|; #

    # We allow changing of the password with this password. We leave
    # everything else untouched

    my $dbh;
    $dbh = $mgr->authen_connect;
    my $sql = sprintf qq{DELETE FROM abrakadabra
                         WHERE NOW() > expires };
    $dbh->do($sql);
    $sql = qq{SELECT *
              FROM abrakadabra
              WHERE user=? AND chpasswd=?};
    my $sth = $dbh->prepare($sql);
    if ( $sth->execute($user, $passwd) and $sth->rows ) {
      # TUT: in the keys of %allow_action we store the methods that are
      # allowed in this request. @allow_submit does something similar.
      $allow_action{"change_passwd"} = undef;
      push @allow_submit, "change_passwd";

      # TUT: by setting $pause->{User}{userid}, we can let change_passwd
      # know who we are dealing with
      $pause->{User}{userid} = $user;
      $userid = $user;

      # TUT: Let's pretend they requested change_passwd. I guess, if we
      # would drop that line, it would still work, but I like redundant
      # coding in such cases
      $param = $req->param("ACTION", "change_passwd"); # override

    } else {
      die  PAUSE::Web2025::Exception->new(ERROR => "You tried to authenticate the
parameter ABRA=$param, but the database doesn't know about this token.", HTTP_STATUS => 401);
    }
    $allow_action{"mailpw"} = undef;
    push @allow_submit, "mailpw";

  } else {

    # warn "unauthorized access (but OK)";
    $allow_action{"mailpw"} = undef;
    push @allow_submit, "mailpw";

  }
  $pause->{allow_action} = [ sort { $a cmp $b } keys %allow_action ];
  # warn "allowaction[@{$pause->{allow_action}}]";
  # warn "allowsubmit[@allow_submit]";
  $pause->{allow_submit} = \@allow_submit;
}

sub _is_allowed_action {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  my %allow_action = map {$_ => undef} @{ $pause->{allow_action} };
  my @allow_submit = @{ $pause->{allow_submit} };

  my $userid = $pause->{User}{userid};

  my $param = shift || $req->param("ACTION");
  # warn "ACTION-param[$param]req[$req]";
  if ($param) {
    if (exists $allow_action{$param}) {
      $pause->{Action} = $param;
    } else {
      warn "$userid tried disallowed action: $param";
      die PAUSE::Web2025::Exception->new(ERROR => "Forbidden", HTTP_STATUS => 403);
    }
  } else {
    # ...they might ask for it in a submit button
  ACTION: for my $action (@allow_submit) {

      # warn "DEBUG: action[$action]";

      # we inherited from a different project: One submitbutton on a page
      if (
          $param = $req->param("pause99_$action\_sub")
         ) {
        # warn "action[$action]";
        $pause->{Action} = $action;
        last ACTION;
      }

      # Also inherited: One submitbutton but also only one textfield,
      # so that RETURN on the textfield submits the form
      if (
          $param = $req->param("pause99_$action\_1")
         ) {
        $req->param("pause99_$action\_sub", $param); # why?
        $pause->{Action} = $action;
        last ACTION;
      }

      # I had intended that parameters matching /_sub.*/ are only used
      # in cases where RETURN might be used instead of SUBMIT. Then I
      # erroneously used "pause99_add_uri_subdirtext"

      my (@partial) = grep /^pause99_\Q$action\E_/, @{$req->params->names};
    PART: for my $partial (@partial) {
        $req->param("pause99_$action\_sub", $partial); # why not $pause->{action_comment}?
        $pause->{Action} = $action;
        last PART;
      }
    }
  }
  my $action = $pause->{Action};
  if (!$action || $req->param('lsw')) { # let submit win

    # the let submit win parameter was introduced when I realized that
    # submit should always win but was afraid that it might break
    # something when we suddenly let submit win in all cases. So new
    # forms should always specify lsw=1 so we can migrate to making it
    # the default some day.

    # New and more generic than the inherited ones above: several submit buttons
    my @params = grep s/^(weak)?SUBMIT_pause99_//i, @{$req->params->names};
    for my $p (@params) {
      # warn "p[$p]";
      for my $a (@allow_submit) {
        if ( substr($p,0,length($a)) eq $a ) {
          $pause->{Action} = $a;
          last;
        }
      }
      last if $pause->{Action};
    }
  }
  $action = $pause->{Action};
  if ($action && !exists $allow_action{$action}) {
    warn "$userid tried disallowed action: $action";
    die PAUSE::Web2025::Exception->new(ERROR => "Forbidden", HTTP_STATUS => 403);
  }
  return 1;
  # warn "action[$action]";
}

1;
