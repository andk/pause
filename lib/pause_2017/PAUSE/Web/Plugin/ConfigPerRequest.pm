package PAUSE::Web::Plugin::ConfigPerRequest;

# XXX: Some of these can be moved into root#check etc,
# and some can be removed now

use Mojo::Base "Mojolicious::Plugin";
use Sys::Hostname;

sub register {
  my ($self, $app, $conf) = @_;
  $app->hook(before_dispatch => \&_before_dispatch);
  $app->hook(before_render => \&_before_render);
  $app->helper(prefer_post => \&_prefer_post);
  $app->helper(need_multipart => \&_need_multipart);
}

sub _before_dispatch {
  my $c = shift;

  $c->stash(".pause" => {}) unless $c->stash(".pause");

  _is_ssl($c);
  _prefer_post($c);
  _can_utf8($c);
  _retrieve_user($c);
  _set_allowed_actions($c);
}

sub _before_render {
  my $c = shift;

  _get_pause_messages($c);
}

sub _is_ssl {
  my $c = shift;
  my $pause = $c->stash(".pause");
  if ($c->req->url->to_abs->scheme eq "https") {
    $pause->{is_ssl} = 1;
  } elsif (Sys::Hostname::hostname() =~ /pause2/) {
    my $header = $c->req->header("X-pause-is-SSL") || 0;
    $pause->{is_ssl} = !!$header;
  }
}

sub _need_multipart {
  my $c = shift;
  my $pause = $c->stash(".pause");
  if (@_) {
    $pause->{need_multipart} = shift;
  }
  $pause->{need_multipart};
}

sub _prefer_post {
  my $c = shift;
  my $pause = $c->stash(".pause");
  return $pause->{prefer_post} = 1; # Because we should always prefer post now

  if (@_) {
    $pause->{prefer_post} = shift;
  }
  $pause->{prefer_post};
}

# pause_1999::authen_user::header
sub _retrieve_user {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;

  my $user = $c->req->env->{REMOTE_USER} or return;

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
      die PAUSE::Web::Exception->new(ERROR => $error);
    } else {
      $pause->{User} = $mgr->fetchrow($sth, "fetchrow_hashref");
    }
  } else {
    die PAUSE::Web::Exception->new(ERROR => $dbh->errstr);
  }
  $sth->finish;

  my $dbh2 = $mgr->authen_connect;
  $sth = $dbh2->prepare("SELECT secretemail
                         FROM $PAUSE::Config->{AUTHEN_USER_TABLE}
                         WHERE $PAUSE::Config->{AUTHEN_USER_FLD}=?");
  $sth->execute($user);
  my($secret_email) = $sth->fetchrow_array;
  $pause->{secret_email} = $secret_email;
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
    die PAUSE::Web::Exception->new(ERROR => $dbh2->errstr);
  }
  $sth->finish;

  delete $pause->{UserGroups}{mlrepr}; # virtual group, disallow in the table
  $sql = qq{SELECT *
            FROM list2user
            WHERE userid=?};
  $sth = $dbh->prepare($sql);
  $sth->execute($user) or die PAUSE::Web::Exception->new(ERROR => $dbh->errstr);
  if ($sth->rows > 0) {
    $pause->{UserGroups}{mlrepr} = undef; # is a virtual group
    my %mlrepr;
    while (my $rec = $mgr->fetchrow($sth, "fetchrow_hashref")) {
      $mlrepr{$rec->{maillistid}} = undef;
    }
    $pause->{IsMailinglistRepresentative} = \%mlrepr;
  }

  $pause->{UserSecrets} = $c->req->env->{"pause.user_secrets"};
  if ( $pause->{UserSecrets}{forcechange} ) {
    $pause->{Action} = "change_passwd"; # ueberschreiben
    $c->req->param(ACTION => "change_passwd"); # faelschen
  }
}

# pause_1999::edit::parameters
sub _set_allowed_actions {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  my ($param, @allow_submit, %allow_action);

  # What is allowed here is allowed to anybody
  @allow_action{
    (
     "pause_04about",
     "pause_04imprint",
     "pause_05news",
     "pause_06history",
     "pause_namingmodules",
     "request_id",
     "who_pumpkin",
     "who_admin",
    )} = ();

  @allow_submit = (
                   "request_id",
                  );

  if ($pause->{User} && $pause->{User}{userid} && $pause->{User}{userid} ne "-") {

    # warn "userid[$pause->{User}{userid}]";

    # All authenticated Users
    for my $command (
                     "add_uri",
                     "change_passwd",
                     "delete_files",
                     "edit_cred",
                     # "edit_mod",
                     "edit_uris",
                     # "apply_mod",
                     "pause_logout",
                     "peek_perms",
                     "reindex",
                     "reset_version",
                     "share_perms",
                     "show_files",
                     "tail_logfile",
                    ) {
      $allow_action{$command} = undef;
      push @allow_submit, $command;
    }

    # Only Mailinglist Representatives
    if (exists $pause->{UserGroups}{mlrepr}) {
      for my $command (
                       "select_ml_action",
                       "edit_ml",
                       # "edit_mod",
                       "reset_version",
                       "show_ml_repr",
                      ) {
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
      for my $command (
                       "add_user",
                       "edit_ml",
                       "select_user",
                       "show_ml_repr",
                       # "add_mod", # all admins may maintain the module list for now
                       # "apply_mod",
                       # "check_xhtml",
                       # "coredump",
                       # "dele_message",
                       # "index_users",
                       # "post_message",
                       "manage_id_requests",
                       # "test_session",
                      ) {
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

      # TUT: Let's pretend they requested change_passwd. I guess, if we
      # would drop that line, it would still work, but I like redundant
      # coding in such cases
      $param = $req->param("ACTION", "change_passwd"); # override

    } else {
      die  PAUSE::Web::Exception->new(ERROR => "You tried to authenticate the
parameter ABRA=$param, but the database doesn't know about this token.");
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

  $param = $req->param("ACTION");
  # warn "ACTION-param[$param]req[$req]";
  if ($param && exists $allow_action{$param}) {
    $pause->{Action} = $param;
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
  # warn "action[$action]";
}

sub _get_pause_messages {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;

  my $user = $pause->{HiddenUser}{userid} || $pause->{User}{userid} or return;

  my $dbh = $mgr->connect;
  my $sth = $dbh->prepare("select * from messages where mto=? AND mstatus='active'");
  $sth->execute($user);
  my @messages;
  if ($sth->rows > 0) {
    while(my $rec = $sth->fetchrow_hashref) {
      push @messages, $rec;
    }
    $pause->{messages} = \@messages;
  }
  $sth->finish;
}

1;
