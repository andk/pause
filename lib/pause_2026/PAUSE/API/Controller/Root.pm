package PAUSE::API::Controller::Root;

use Mojo::Base "Mojolicious::Controller";
use HTTP::Date ();
use Time::Duration ();
use PAUSE;
use Digest::SHA;

sub check {
  my $c = shift;

  if (my $res = _pause_is_closed()) {
    $c->render(json => $res, status => 503);
    return;
  }

  return 1;
}

sub _pause_is_closed {
  my $dti = PAUSE::downtimeinfo();
  my $downtime = $dti->{downtime};
  my $willlast = $dti->{willlast};

  # TODO: just ignore scheduled downtime for now
  if (time >= $downtime && time < $downtime + $willlast) {
    my $delta = $downtime + $willlast - time;
    my $expr = Time::Duration::duration($delta);
    my $willlast_dur = Time::Duration::duration($willlast);
    return {
      closed => {
        delta => $expr,
        will_last => $willlast_dur,
      }
    };
  }
  return;
}

sub check_token {
  my $c = shift;
  my $header = $c->req->headers->header('Authorization');
  die PAUSE::Web::Exception->new(ERROR => 'No authorization header') unless $header;
  $header =~ s/Bearer\s+//i or die PAUSE::Web::Exception->new(ERROR => 'No Bearer token');

  my ($user, $token_id, $token) = split ':', $header;
  die PAUSE::Web::Exception->new(ERROR => 'Invalid token') if !$user or !$token_id or !$token;

  my $pause = $c->stash('.pause');
  if (!$pause) {
    $c->stash(".pause" => $pause = {});
  }

  my $mgr = $c->app->pause;
  my $dbh = $mgr->authen_connect or die;
  my $row = $dbh->selectrow_hashref(qq{
    SELECT user, ip_ranges, scope FROM auth_tokens WHERE user = ? and token_id = ? and token_hash = ? and revoked = 0 and expires_at > NOW()
  }, undef, $user, $token_id, Digest::SHA::hmac_sha256_hex($token_id, $token));
  die PAUSE::Web::Exception->new(ERROR => 'Invalid token') unless $row;

  $pause->{token_info} = $row;

  if (my $ip_ranges = $row->{ip_ranges}) {
    require Net::CIDR;
    my $ip = $c->tx->remote_address;
    my @list = split /\n/, $ip_ranges;
    die PAUSE::Web::Exception->new(ERROR => "Out of allowed IP ranges") unless Net::CIDR::cidrlookup($ip, @list);
  }

  _retrieve_user($c, $row->{user});
}

# mostly taken from PAUSE::Web::Plugin::ConfigPerRequest
sub _retrieve_user {
  my ($c, $user) = @_;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;

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
        $error = "User '$user' set to nologin. Your account may have been included in a precautionary password reset in the wake of a data breach
 incident at some other site. Please talk to modules\@perl.org to find out how to proceed";
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
  $pause->{User}{secretemail} = $secret_email;
  $sth->finish;
}

1;
