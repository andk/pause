package pause_1999::authen_user;
use pause_1999::main;
use Apache ();
use Apache::Constants qw( AUTH_REQUIRED MOVED OK SERVER_ERROR );
use base 'Class::Singleton';
use PAUSE ();
use strict;
our $VERSION = sprintf "%d", q$Rev$ =~ /(\d+)/;

=comment

Apache::AuthenDBI was not enough for my taste. I want the username
case insensitive but the password case sensitive. I want to store the
user record early and this seems an appropriate place.



=cut

sub header {
  my pause_1999::authen_user $self = shift;
  my pause_1999::main $mgr = shift;
  my $r = $mgr->{R};
  if (my $u = $r->connection->user) {

    #This is a database application with nearly all users having write access
    #Write access means expiration any moment
    my $headers = $r->headers_out;
    $headers->{'Pragma'} = $headers->{'Cache-control'} = 'no-cache';
    $r->no_cache(1);
    # This is annoying when we ask for the who-is-who list and it
    # hasn't changed since the last time, but for most cases it's
    # safer to expire

    my($userhash);

    # we are not authenticating here, we retrieve the user record from
    # the open database. Thus
    my $dbh = $mgr->connect; # and not authentication database
    local($dbh->{RaiseError}) = 0;
    my($sql,$sth);
    $sql = qq{SELECT *
              FROM users
              WHERE userid=?};
    $sth = $dbh->prepare($sql);
    if ($sth->execute($u)) {
      $mgr->{User} = $mgr->fetchrow($sth, "fetchrow_hashref");
    } else {
      die Apache::HeavyCGI::Exception->new(ERROR => $dbh->errstr);
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
      die Apache::HeavyCGI::Exception->new(ERROR => $dbh2->errstr);
    }
    $sth->finish;

    delete $mgr->{UserGroups}{mlrepr}; # virtual group, disallow in the table
    $sql = qq{SELECT *
              FROM list2user
              WHERE userid=?};
    $sth = $dbh->prepare($sql);
    $sth->execute($u) or die Apache::HeavyCGI::Exception->new(ERROR => $dbh->errstr);
    if ($sth->rows > 0) {
      $mgr->{UserGroups}{mlrepr} = undef; # is a virtual group
      $mgr->{IsMailinglistRepresentative} = {};
      while (my $rec = $mgr->fetchrow($sth, "fetchrow_hashref")) {
        $mgr->{IsMailinglistRepresentative}{$rec->{maillistid}} = undef;
      }
    }

    $mgr->{UserSecrets} = $r->pnotes("usersecrets");
    if ( $mgr->{UserSecrets}{forcechange} ) {
      $mgr->{Action} = "change_passwd"; # ueberschreiben
      $mgr->{CGI}->param(ACTION=>"change_passwd"); # faelschen
    }
  }
}

sub handler {
  my($r) = @_;

  my $cookie;
  my $args;
  my $uri = $r->uri;
  # warn "Watch: uri[$uri]";
  if ($cookie = $r->header_in("Cookie")) {
    # since we have bugzilla, we send a different cookie all the time
    # warn "cookie[$cookie]";
    if ( $cookie =~ /please_renegotiate_username/ ) {
      warn "Watch: cookie[$cookie]";
      $r->err_header_out("Set-Cookie","please_renegotiate_username; path=$uri; expires=Sat, 01-Oct-1974 00:00:00 GMT");
      return AUTH_REQUIRED;
    }
  }
  if ($args = $r->args) {
    # warn "Watch: args[$args]";
    if ( $args =~ s/please_renegotiate_username// ) {
      $r->err_header_out("Set-Cookie","please_renegotiate_username; path=$uri; expires=Sat, 01-Oct-2027 00:00:00 GMT");
      $args = "?$args" if $args;
      $r->header_out("Location","$uri$args");
      return MOVED;
    }
  }


  return OK unless $r->is_initial_req; #only the first internal request
  my($res, $sent_pw) = $r->get_basic_auth_pw;

  # warn "res[$res]sent_pw[$sent_pw]";

  return $res if $res; #decline if not Basic
  my $user_sent = $r->connection->user;

  my $attr = {
	      data_source      => $PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME},
	      username	       => $PAUSE::Config->{AUTHEN_DATA_SOURCE_USER},
	      password	       => $PAUSE::Config->{AUTHEN_DATA_SOURCE_PW},
	      pwd_table	       => $PAUSE::Config->{AUTHEN_USER_TABLE},
	      uid_field	       => $PAUSE::Config->{AUTHEN_USER_FLD},
	      pwd_field	       => $PAUSE::Config->{AUTHEN_PASSWORD_FLD},
	     };

  my $dbh;
  unless ($dbh = DBI->connect($attr->{data_source},
			      $attr->{username},
			      $attr->{password})) {
    $r->log_reason(" db connect error with $attr->{data_source}",
		   $r->uri);
    my $redir = $r->uri;
    $redir =~ s/authen//;
    $r->connection->user("-");
    $r->custom_response(SERVER_ERROR, $redir);
    return SERVER_ERROR;
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
    $r->log_reason("can not prepare statement: $DBI::errstr",
		   $r->uri);
    $dbh->disconnect;
    return SERVER_ERROR;
  }
  for my $user (@try_user){
    unless ($sth->execute($user)) {
      $r->log_reason(" can not execute statement: $DBI::errstr",
		     $r->uri);
      $dbh->disconnect;
      return SERVER_ERROR;
    }

    if ($sth->rows == 1){
      $user_record = pause_1999::main::->fetchrow($sth, "fetchrow_hashref");
      $r->connection->user($user);
      last;
    }
  }
  $sth->finish;
  $dbh->disconnect;

  my $crypt_pw  = $user_record->{$attr->{pwd_field}};
  if ($crypt_pw) {
    my($crypt_got) = crypt($sent_pw,$crypt_pw);
    if ($crypt_got eq $crypt_pw){
      $r->pnotes("usersecrets", $user_record);
      return OK;
    } else {
      warn sprintf "crypt_pw[%s]crypt_got[%s]uri[%s]auth_required[%d]",
	  $crypt_pw, $crypt_got, $r->uri, AUTH_REQUIRED;
    }
  }

  $r->note_basic_auth_failure;
  return AUTH_REQUIRED;
}

1;
