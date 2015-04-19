package pause_1999::authen_user;
use pause_1999::main;
use HTTP::Status qw(:constants);
use base 'Class::Singleton';
use PAUSE ();
use PAUSE::Crypt;
use strict;
our $VERSION = "1052";

=comment

Apache::AuthenDBI was not enough for my taste. I want the username
case insensitive but the password case sensitive. I want to store the
user record early and this seems an appropriate place.



=cut

sub header {
  my pause_1999::authen_user $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  if (my $u = $req->user) {
    #This is a database application with nearly all users having write access
    #Write access means expiration any moment
    my $headers = $mgr->{RES}->headers;
    $headers->header('Pragma', 'no-cache'); $headers->header('Cache-control', 'no-cache');
    # XXX: $res->no_cache(1);
    # This is annoying when we ask for the who-is-who list and it
    # hasn't changed since the last time, but for most cases it's
    # safer to expire

    # we are not authenticating here, we retrieve the user record from
    # the open database. Thus
    my $dbh = $mgr->connect; # and not authentication database
    local($dbh->{RaiseError}) = 0;
    my($sql,$sth);
    $sql = qq{SELECT *
              FROM users
              WHERE userid=? AND ustatus != 'nologin'};
    $sth = $dbh->prepare($sql);
    if ($sth->execute($u)) {
      if (0 == $sth->rows) {
        my($sql7,$sth7);
        $sql7 = qq{SELECT *
              FROM users
              WHERE userid=?};
        $sth7 = $dbh->prepare($sql7);
        $sth7->execute($u);
        my $error;
        if ($sth7->rows > 0) {
          $error = "User '$u' set to nologin. Many users with an insecure password have got their password reset recently because of an incident on perlmonks.org. Please talk to modules\@perl.org to find out how to proceed";
        } else {
          $error = "User '$u' not known";
        }
        die PAUSE::HeavyCGI::Exception->new(ERROR => $error);
      } else {
        $mgr->{User} = $mgr->fetchrow($sth, "fetchrow_hashref");
      }
    } else {
      die PAUSE::HeavyCGI::Exception->new(ERROR => $dbh->errstr);
    }
    $sth->finish;

    my $dbh2 = $mgr->authen_connect;
    $sth = $dbh2->prepare("SELECT secretemail
                           FROM $PAUSE::Config->{AUTHEN_USER_TABLE}
                           WHERE $PAUSE::Config->{AUTHEN_USER_FLD}=?");
    $sth->execute($u);
    my($secretemail) = $sth->fetchrow_array;
    $mgr->{User}{secretemail} = $secretemail;
    $sth->finish;

    $sql = qq{SELECT *
              FROM grouptable
              WHERE user=?};
    $sth = $dbh2->prepare($sql);
    if ($sth->execute($u)) {
      $mgr->{UserGroups} = {};
      while (my $rec = $mgr->fetchrow($sth, "fetchrow_hashref")) {
	$mgr->{UserGroups}{$rec->{ugroup}} = undef;
      }
    } else {
      die PAUSE::HeavyCGI::Exception->new(ERROR => $dbh2->errstr);
    }
    $sth->finish;

    delete $mgr->{UserGroups}{mlrepr}; # virtual group, disallow in the table
    $sql = qq{SELECT *
              FROM list2user
              WHERE userid=?};
    $sth = $dbh->prepare($sql);
    $sth->execute($u) or die PAUSE::HeavyCGI::Exception->new(ERROR => $dbh->errstr);
    if ($sth->rows > 0) {
      $mgr->{UserGroups}{mlrepr} = undef; # is a virtual group
      $mgr->{IsMailinglistRepresentative} = {};
      while (my $rec = $mgr->fetchrow($sth, "fetchrow_hashref")) {
        $mgr->{IsMailinglistRepresentative}{$rec->{maillistid}} = undef;
      }
    }

    $mgr->{UserSecrets} = $req->env->{'psgix.pnotes'}{usersecrets};
    if ( $mgr->{UserSecrets}{forcechange} ) {
      $mgr->{Action} = "change_passwd"; # ueberschreiben
      $mgr->{REQ}->param(ACTION=>"change_passwd"); # faelschen
    }
  }
}

sub handler {
  my($req) = @_;

  my $cookie;
  my $uri = $req->path || "";
  my $args = $req->uri->query;
  warn "WATCH: uri[$uri]args[$args]";
  if ($cookie = $req->header('Cookie')) {
    if ( $cookie =~ /logout/ ) {
      warn "WATCH: cookie[$cookie]";
      my $res = $req->new_response(HTTP_UNAUTHORIZED);
      $res->cookies->{logout} = {
        value => '',
        path => $uri,
        expires => "Sat, 01-Oct-1974 00:00:00 UTC",
      };
      return $res;
    }
  }
  if ($args) {
    my $logout;
    if ( my $logout = $req->query_parameters->get('logout') ) {
      warn "WATCH: logout[$logout]";
      if ($logout =~ /^1/) {
        my $res = $req->new_response(HTTP_MOVED_PERMANENTLY);
        $res->cookies->{logout} = {
            value => '',
            path => $uri,
            expires => "Sat, 01-Oct-2027 00:00:00 UTC",
        };
        $res->header("Location",$uri);
        return $res;
      } elsif ($logout =~ /^2/) { # badname
        my $redir = $req->base;
        $redir->path($req->uri->path);
        $redir->userinfo('baduser:badpass');
        warn "redir[$redir]";
        my $res = $req->new_response(HTTP_MOVED_PERMANENTLY);
        $res->header("Location",$redir);
        return $res;
      } elsif ($logout =~ /^3/) { # cancelnote
        return  HTTP_UNAUTHORIZED;
      }
    }
  }
  # return HTTP_OK unless $r->is_initial_req; #only the first internal request

  my $auth = $req->env->{HTTP_AUTHORIZATION} or return HTTP_UNAUTHORIZED;
  return HTTP_UNAUTHORIZED unless $auth =~ /^Basic (.*)$/i; #decline if not Basic
  my($user_sent, $sent_pw) = split /:/, (MIME::Base64::decode($1) || ":"), 2;

  my $attr = {
	      data_source      => $PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME},
	      username	       => $PAUSE::Config->{AUTHEN_DATA_SOURCE_USER},
	      password	       => $PAUSE::Config->{AUTHEN_DATA_SOURCE_PW},
	      pwd_table	       => $PAUSE::Config->{AUTHEN_USER_TABLE},
	      uid_field	       => $PAUSE::Config->{AUTHEN_USER_FLD},
	      pwd_field	       => $PAUSE::Config->{AUTHEN_PASSWORD_FLD},
	     };

  my $dbh;
  warn "DEBUG: attr.data_source[$attr->{data_source}]";
  unless ($dbh = DBI->connect($attr->{data_source},
			      $attr->{username},
			      $attr->{password})) {
    $req->logger->({level => 'error', message => " db connect error with $attr->{data_source} ".$req->path });
    my $redir = $req->path;
    $redir =~ s/authen//;
    delete $req->env->{REMOTE_USER};
    return $req->new_response(HTTP_INTERNAL_SERVER_ERROR, undef, $redir);
  }

  # generate statement
  my $user_record;
  my @try_user = $user_sent;
  push @try_user, uc $user_sent if $user_sent ne uc $user_sent;

  my $statement = qq{SELECT * FROM $attr->{pwd_table}
                     WHERE $attr->{uid_field}=?};
  # prepare statement
  my $sth;
  unless ($sth = $dbh->prepare($statement)) {
    $req->logger->({level => 'error', message => "can not prepare statement: $DBI::errstr". $req->path });
    $dbh->disconnect;
    return $req->new_response(HTTP_INTERNAL_SERVER_ERROR);
  }
  for my $user (@try_user){
    unless ($sth->execute($user)) {
      $req->logger->({level => 'error', message => " can not execute statement: $DBI::errstr" . $req->path });
      $dbh->disconnect;
      return $req->new_response(HTTP_INTERNAL_SERVER_ERROR);
    }

    if ($sth->rows == 1){
      $user_record = pause_1999::main::->fetchrow($sth, "fetchrow_hashref");
      $req->env->{REMOTE_USER} = $user;
      last;
    }
  }
  $sth->finish;

  my $crypt_pw  = $user_record->{$attr->{pwd_field}};
  if ($crypt_pw) {
    if (PAUSE::Crypt::password_verify($sent_pw, $crypt_pw)) {
      PAUSE::Crypt::maybe_upgrade_stored_hash({
        password => $sent_pw,
        old_hash => $crypt_pw,
        dbh      => $dbh,
        username => $user_record->{user},
      });
      $req->env->{'psgix.pnotes'}{usersecrets} = $user_record;
      $dbh->do
          ("UPDATE usertable SET lastvisit=NOW() where user=?",
           +{},
           $user_record->{user},
          );
      $dbh->disconnect;
      return HTTP_OK;
    } else {
      warn sprintf "crypt_pw[%s]user[%s]uri[%s]auth_required[%d]",
	  $crypt_pw, $user_record->{user}, $req->path, HTTP_UNAUTHORIZED;
    }
  }

  $dbh->disconnect;
  return HTTP_UNAUTHORIZED;
}

1;
