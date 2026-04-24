package PAUSE::Web2026::Controller::User::Tokens;

use Mojo::Base "Mojolicious::Controller";
use HTTP::Date ();
use File::pushd;
use PAUSE ();
use Crypt::PRNG;
use Digest::SHA;

sub list {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $req = $c->req;
  my $mgr = $c->app->pause;
  my $u = $c->active_user_record;

  my $dbh = $mgr->authen_connect;

  if ($req->param('revoke_tokens_sub')) {
    my $sth_update = $dbh->prepare('UPDATE auth_tokens SET revoked = 1 WHERE id = ? AND user = ?');
    my $sth_select = $dbh->prepare('SELECT user, token_id, revoked FROM auth_tokens WHERE id = ?');
    for my $id (@{$req->every_param('revoke_tokens')}) {
      $sth_select->execute($id);
      my $target = $sth_select->fetchrow_hashref;
      if ($target) {
        my $token_id = $target->{token_id};
        my $is_revoked = $sth_update->execute($id, $u->{userid});
        if ($is_revoked) {
          $mgr->log({level => 'info', message => "Revoked a token $token_id for $u->{userid}"});
        } else {
          if ($target->{revoked}) {
            $mgr->log({level => 'warn', message => "Failed to revoke a token $token_id for $u->{userid}: already revoked"});
          } elsif ($target->{userid} ne $u->{userid}) {
            $mgr->log({level => 'error', message => "Failed to revoke a token $token_id for $u->{userid}: wrong userid"});
          }
        }
      } else {
        $mgr->log({level => 'warn', message => "Failed to revoke a token for $u->{userid}: unknown token"});
      }
    }
  }

  my $tokens = $dbh->selectall_arrayref(qq{
    SELECT id, token_id, description, expires_at
    FROM auth_tokens
    WHERE user = ? AND revoked = 0 ORDER BY created_at DESC
  }, {Slice => +{}}, $u->{userid});

  $pause->{tokens} = $tokens;
}

sub generate {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;

  if ($req->param('new_token_sub')) {
    my $token = Crypt::PRNG::random_bytes_hex(32);
    my $token_id = Crypt::PRNG::random_bytes_hex(4);
    my $token_hash = Digest::SHA::hmac_sha256_hex($token, $token_id);
    my $description = $req->param('new_token_description');
    my $expires_in  = $req->param('new_token_expires_in') || 180;
    my $ip_ranges   = $req->param('new_token_ip_ranges');

    # right now we have only one scope
    my $scope = 'upload:distributions';

    my $expires_at  = time;
    $expires_in += 0;
    $expires_in = 1 if $expires_in < 1;
    $expires_in = 180 if $expires_in > 180;
    $expires_at += int($expires_in) * 24 * 60 * 60;

    if ($ip_ranges) {
      require Net::CIDR;
      my @ip_errors;
      # TODO: how many CIDRs should we accept?
      for my $ip (split /\n/, $ip_ranges) {
        if (!Net::CIDR::cidrvalidate($ip)) {
          push @ip_errors, $ip;
        }
      }
      if (@ip_errors) {
        $pause->{error}{ip_ranges_error} = join "; ", @ip_errors;
      }
    }
    if (!$pause->{error}) {
      my $dbh = $mgr->authen_connect;
      my $is_inserted = $dbh->do(qq{
        INSERT INTO auth_tokens
        (user, token_id, token_hash, description, expires_at, scope, ip_ranges)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      }, undef, $u->{userid}, $token_id, $token_hash, $description, Time::Piece->new($expires_at)->strftime('%Y-%m-%d %H:%M:%S'), $scope, $ip_ranges);
      if ($is_inserted) {
        $mgr->log({level => 'info', message => "Generated a new token $token_id for $c->{userid}"});
        $c->flash(new_token => join ':', $u->{userid}, $token_id, $token);
        return $c->redirect_to($c->my_url);
      } else {
        $pause->{error}{generation_failed} = 1;
      }
    }
    for my $key (qw(description scope expires_at ip_ranges)) {
      $pause->{$key} = $req->param("pause_99_new_token_$key");
    }
  }
}

1;
