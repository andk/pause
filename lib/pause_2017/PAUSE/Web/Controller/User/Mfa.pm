package PAUSE::Web::Controller::User::Mfa;

use Mojo::Base "Mojolicious::Controller";
use Auth::GoogleAuth;
use PAUSE::Crypt;
use Crypt::URandom qw(urandom);
use Convert::Base32 qw(encode_base32);
use Imager::QRCode qw(plot_qrcode);
use URI;

sub edit {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;

  my $auth = $c->app->pause->authenticator_for($u);
  $pause->{mfa_qrcode} = _generate_qrcode($auth);
  if (!$u->{mfa_secret32}) {
    my $dbh = $mgr->authen_connect;
    my $tbl = $PAUSE::Config->{AUTHEN_USER_TABLE};
    my $sql = "UPDATE $tbl SET mfa_secret32 = ?, changed = ?, changedby = ? WHERE user = ?";
    $dbh->do($sql, undef, $auth->secret32, time, $pause->{User}{userid}, $u->{userid})
      or push @{$pause->{ERROR}}, sprintf(qq{Could not enter the data into the database: <i>%s</i>.},$dbh->errstr);
  }

  if (uc $req->method eq 'POST' and $req->param("pause99_mfa_sub")) {
    my $code = $req->param("pause99_mfa_code");
    $req->param("pause99_mfa_code", undef);
    my $verified;
    if ($code =~ /\A[0-9]{6}\z/ && $auth->verify($code)) {
        $verified = 1;
    } elsif ($code =~ /\A[a-z0-9]{5}\-[a-z0-9]{5}\z/ && $u->{mfa_recovery_codes} && $req->param("pause99_mfa_reset")) {
        my @recovery_codes = split / /, $u->{mfa_recovery_codes} // '';
        if (grep { PAUSE::Crypt::password_verify($code, $_) } @recovery_codes) {
            $verified = 1;
        }
    }
    unless ($verified) {
        $pause->{error}{invalid_code} = 1;
        return;
    }
    my ($mfa, $secret32, $recovery_codes);
    if ($req->param("pause99_mfa_reset")) {
        $mfa = 0;
        $secret32 = undef;
        $recovery_codes = undef;
        $c->flash(mfa_disabled => 1);
    } else {
        $mfa = 1;
        $secret32 = $auth->secret32;
        $c->flash(mfa_enabled => 1);
        my @codes = _generate_recovery_codes();
        $c->flash(recovery_codes => \@codes);
        $recovery_codes = join " ", map { PAUSE::Crypt::hash_password($_) } @codes;
    }
    my $dbh = $mgr->authen_connect;
    my $tbl = $PAUSE::Config->{AUTHEN_USER_TABLE};
    my $sql = "UPDATE $tbl SET mfa = ?, mfa_secret32 = ?, mfa_recovery_codes = ?, changed = ?, changedby = ? WHERE user = ?";
    if ($dbh->do($sql, undef, $mfa, $secret32, $recovery_codes, time, $pause->{User}{userid}, $u->{userid})) {
      my $mailblurb = $c->render_to_string("email/user/mfa/edit", format => "email");
      my $header = {Subject => "User update for $u->{userid}"};
      my @to = $u->{secretemail};
      $mgr->send_mail_multi(\@to, $header, $mailblurb);
    } else {
      push @{$pause->{ERROR}}, sprintf(qq{Could not enter the data
        into the database: <i>%s</i>.},$dbh->errstr);
    }
    $c->redirect_to('/authenquery?ACTION=mfa');
  }
}

sub _generate_recovery_codes {
    my @codes;
    for (1 .. 8) {
        my $code = encode_base32(urandom(6));
        $code =~ tr/lo/89/;
        $code =~ s/^(.{5})/$1-/;
        push @codes, $code;
    }
    @codes;
}

# using $auth->qr_code directly is handy but insecure
sub _generate_qrcode {
    my $auth = shift;
    my $otpauth = $auth->qr_code(undef, undef, undef, 1);
    my $img = plot_qrcode($otpauth, { casesensitive => 1 });
    $img->write(data => \my $qr_png, type => 'png') or die "Failed to write image: " . $img->errstr;
    my $data = URI->new("data:");
    $data->data($qr_png);
    $data->media_type('image/png');
    $data;
}

1;
