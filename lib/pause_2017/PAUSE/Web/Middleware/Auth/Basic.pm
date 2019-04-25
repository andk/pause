package PAUSE::Web::Middleware::Auth::Basic;

use Mojo::Base "Plack::Middleware";
use MIME::Base64;
use HTTP::Status qw/:constants/;
use PAUSE ();
use PAUSE::Crypt;
use Plack::Request;
use DBI;

has "context";

sub call {
  my ($self, $env) = @_;

  local $SIG{__WARN__} = sub {
    my $message = shift;
    chomp $message;
    Log::Dispatch::Config->instance->log(
      level => 'warn',
      message => $message,
    );
  };

  my $res = eval { $self->authenticate($env) };
  if ($@) {
    Log::Dispatch::Config->instance->log(
      level => 'error',
      message => "AUTH ERROR: $@",
    );
  }

  return $res->finalize if ref $res;
  return $self->unauthorized($env) unless $res == HTTP_OK;
  return $self->app->($env);
}

sub unauthorized {
  my ($self, $env) = @_;
  my $body = delete $env->{"pause.auth_error"} || 'Authorization required';
  return [
    401,
    [ 'Content-Type' => 'text/plain',
      'Content-Length' => length $body,
      'WWW-Authenticate' => 'Basic realm="PAUSE"' ],
    [ $body ],
  ];
}

# pause_1999::authen_user::handler
sub authenticate {
  my ($self, $env) = @_;

  my $req = Plack::Request->new($env);

  my $cookie;
  my $uri = $req->path || "";
  $uri = "/pause".$uri unless $uri =~ m!/pause/!; # add mount point
  my $args = $req->uri->query || "";
  warn "WATCH: uri[$uri]args[$args]";
  if ($cookie = $req->headers->header('Cookie')) {
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
        $res->headers->header("Location",$uri);
        return $res;
      } elsif ($logout =~ /^2/) { # badname
        my $redir = $req->base;
        $redir->path($req->uri->path);
        $redir->userinfo('baduser:badpass');
        warn "redir[$redir]";
        my $res = $req->new_response(HTTP_MOVED_PERMANENTLY);
        $res->headers->header("Location",$redir);
        return $res;
      } elsif ($logout =~ /^3/) { # cancelnote
        return  HTTP_UNAUTHORIZED;
      }
    }
  }

  my $auth = $env->{HTTP_AUTHORIZATION} or return HTTP_UNAUTHORIZED;
  return HTTP_UNAUTHORIZED unless $auth =~ /^Basic (.*)$/i; #decline if not Basic
  my($user_sent, $sent_pw) = split /:/, (MIME::Base64::decode($1) || ":"), 2;

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
    Log::Dispatch::Config->instance->log(level => 'error', message => " db connect error with $attr->{data_source} ".$req->path);
    my $redir = $req->path;
    $redir =~ s/authen//;
    delete $env->{REMOTE_USER};
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
    Log::Dispatch::Config->instance->log(level => 'error', message => "can not prepare statement: $DBI::errstr". $req->path);
    $dbh->disconnect;
    return $req->new_response(HTTP_INTERNAL_SERVER_ERROR);
  }
  for my $user (@try_user){
    unless ($sth->execute($user)) {
      Log::Dispatch::Config->instance->log(level => 'error', message => " can not execute statement: $DBI::errstr" . $req->path);
      $dbh->disconnect;
      return $req->new_response(HTTP_INTERNAL_SERVER_ERROR);
    }

    if ($sth->rows == 1){
      $user_record = $self->context->fetchrow($sth, "fetchrow_hashref");
      $env->{REMOTE_USER} = $user;
      last;
    }
  }
  $sth->finish;

  # delete not to be carried around
  my $crypt_pw  = delete $user_record->{$attr->{pwd_field}};
  if ($crypt_pw) {
    if (PAUSE::Crypt::password_verify($sent_pw, $crypt_pw)) {
      PAUSE::Crypt::maybe_upgrade_stored_hash({
        password => $sent_pw,
        old_hash => $crypt_pw,
        dbh      => $dbh,
        username => $user_record->{user},
      });
      $env->{"pause.user_secrets"} = $user_record;
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
