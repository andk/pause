package PAUSE::Web::Plugin::UserRegistration;

use Mojo::Base "Mojolicious::Plugin";
use PAUSE::Crypt;
use HTTP::Tiny 0.059;
use IO::Socket::SSL 1.56;
use Net::SSLeay 1.49;
use JSON::XS;

sub register {
  my ($self, $app, $conf) = @_;
  $app->helper(verify_recaptcha => \&_verify_recaptcha);
  $app->helper(set_onetime_password => \&_set_onetime_password);
  $app->helper(send_otp_email => \&_send_otp_email);
  $app->helper(send_welcome_email => \&_send_welcome_email);
  $app->helper(auto_registration_rate_limit_ok => \&_auto_registration_rate_limit_ok);
}

# return values are $ok, $err; $ok undef means unknown validation;
# $ok defined true/false indicates whether verification succeeded.  If
# completed but failed, $err will have error message(s).
sub _verify_recaptcha {
    my ($c, $token) = @_;
    if ( ! $PAUSE::Config->{RECAPTCHA_SECRET_KEY} ) {
        warn "_verify_recaptcha: RECAPTCHA_SECRET_KEY not available\n";
        return;
    }

    my $ht = HTTP::Tiny->new;
    my $ok = undef;
    my $err = "";
    eval {
        my $res = $ht->post_form(
            "https://www.google.com/recaptcha/api/siteverify",
            { secret => $PAUSE::Config->{RECAPTCHA_SECRET_KEY}, response => $token }
        );
        if ( $res->{success} ) {
            my $data = decode_json( $res->{content} );
            $ok = $data->{success};
            if ( ref $err eq 'ARRAY' ) {
                $err = join(", ", @$err)
            }
        }
    };

    return $ok, $err;
}

sub _set_onetime_password {
    my ($c, $userid, $email) = @_;
    my $pause = $c->stash('.pause');
    my $mgr = $c->app->pause;

    my $onetime = sprintf "%08x", rand(0xffffffff);

    my $sql = qq{INSERT INTO $PAUSE::Config->{AUTHEN_USER_TABLE} (
                    $PAUSE::Config->{AUTHEN_USER_FLD},
                    $PAUSE::Config->{AUTHEN_PASSWORD_FLD},
                        secretemail,
                        forcechange,
                        changed,
                        changedby
                    ) VALUES (
                    ?,?,?,?,?,?
                    )};
    my $pwenc = PAUSE::Crypt::hash_password($onetime);
    my $dbh = $mgr->authen_connect;
    local($dbh->{RaiseError}) = 0;
    my $rc = $dbh->do($sql,undef,$userid,$pwenc,$email,1,time,$pause->{User}{userid});
    die PAUSE::Web::Exception
        ->new(ERROR =>
              [qq{Query [$sql] failed. Reason:},
               $DBI::errstr,
               qq{This is very unfortunate as we have no option to rollback. The user is now registered in mod.users and could not be
registered in authen_pause.$PAUSE::Config->{AUTHEN_USER_TABLE}}]
             ) unless $rc;
    $dbh->disconnect;

    return $onetime;
}

sub _send_otp_email {
    my ($c, $userid, $email, $onetime) = @_;
    my $pause = $c->stash('.pause');
    my $mgr = $c->app->pause;

    local $pause->{email}   = $email;
    local $pause->{onetime} = $onetime;
    my $otpwblurb = $c->render_to_string("email/admin/user/onetime_password", format => "email");
    my $header = {
        Subject => qq{Temporary PAUSE password for $userid},
    };
    my $header_str = join "\n", map {"$_: $header->{$_}"} keys %$header;
    warn "header[$header_str]otpwblurb[$otpwblurb]";
    $mgr->send_mail_multi( [ $email, PAUSE::Email->report_email_header_object ], $header, $otpwblurb);
}

sub _send_welcome_email {
    my ($c, $to, $userid, $email, $fullname, $homepage, $entered_by) = @_;
    my $pause = $c->stash('.pause');
    my $mgr = $c->app->pause;

    local $pause->{userid}     = $userid;
    local $pause->{email}      = $email;
    local $pause->{fullname}   = $fullname;
    local $pause->{homepage}   = $homepage;
    local $pause->{entered_by} = $entered_by;
    my $blurb = $c->render_to_string("email/admin/user/welcome_user", format => "email");

    my $header = { Subject => "Welcome new user $userid" };
    $mgr->send_mail_multi($to,$header,$blurb);

    return ($header->{Subject}, $blurb);
}

sub _auto_registration_rate_limit_ok {
    my $c = shift;
    my $pause = $c->stash('.pause');
    my $mgr = $c->app->pause;

    my $limit = $PAUSE::Config->{RECAPTCHA_DAILY_LIMIT};

    # $limit 0 or undef means "no limit"
    return 1 if !$limit;

    my $dbh = $mgr->connect;
    my ($new_users) = $dbh->selectrow_array(
        qq{ SELECT COUNT(*) FROM users where introduced > ?  },
        undef, time - 24 * 3600,
    );
    warn "new_user $new_users <= limit $limit?";

    return $new_users <= $limit;
}

1;
