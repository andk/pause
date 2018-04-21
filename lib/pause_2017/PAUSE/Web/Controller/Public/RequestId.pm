package PAUSE::Web::Controller::Public::RequestId;

use Mojo::Base "Mojolicious::Controller";
use PAUSE::Web::Util::Encode;

sub request {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $valid_userid = $mgr->config->valid_userid;

  # first time: form
  # second time with error: error message + form
  # second time without error: OK message
  # bot debunked? => "Thank you!"

  my $showform = 0;
  my $regOK = 0;

  if ($req->param('url')) { # debunked
    $c->stash(format => 'text');
    $c->render(text => "Thank you!");
    return;
  }

  my $fullname  = $req->param('pause99_request_id_fullname') || "";
  my $ufullname = PAUSE::Web::Util::Encode::any2utf8($fullname);
  if ($ufullname ne $fullname) {
    $req->param("pause99_request_id_fullname" => $ufullname);
    $fullname = $ufullname;
  }
  my $email     = $req->param('pause99_request_id_email') || "";
  my $homepage  = $req->param('pause99_request_id_homepage') || "";
  my $userid    = $req->param('pause99_request_id_userid') || "";
  my $rationale = $req->param("pause99_request_id_rationale") || "";
  my $token     = $req->param("g-recaptcha-response") || "";
  my $urat = PAUSE::Web::Util::Encode::any2utf8($rationale);
  if ($urat ne $rationale) {
    $req->param("pause99_request_id_rationale" => $urat);
    $rationale = $urat;
  }
  warn sprintf(
               "userid[%s]Valid_Userid[%s]args[%s]",
               $userid,
               $valid_userid,
               scalar($req->url->query)||"",
              );

  if ( $req->param("SUBMIT_pause99_request_id_sub") ) {
    # check for errors

    my @errors = ();
    if ( $fullname ) {
      unless ($fullname =~ /[ ]/) {
        push @errors, "Name does not look like a full civil name. Please accept our apologies if you believe we're wrong. In this case please write to @{$PAUSE::Config->{ADMINS}}.";
      }
    } else {
      push @errors, "You must supply a name\n";
    }
    unless( $email ) {
      push @errors, "You must supply an email address\n";
    }
    if ( $rationale ) {

      $rationale =~ s/^\s+//;
      $rationale =~ s/\s+$//;
      $rationale =~ s/\s+/ /;
      push @errors, "Thank you for giving us a short description of
        what you're planning to contribute, but frankly, this looks a
        bit too short" if length($rationale)<10;
      push @errors, "Please do not use HTML links in your description of
        what you're planning to contribute" if $rationale =~ /<\s*a\s+href\s*=/ims;

      my $url_count =()= $rationale =~ m{https?://}gi;
      push @errors, "Please do not include more than one URL in your description of
        what you're planning to contribute" if $url_count > 1;

    } else {

      push @errors, "You must supply a short description of what
        you're planning to contribute\n";

    }
    if ( $userid ) {
      $userid = uc $userid;
      $req->param('pause99_request_id_userid' => $userid);
      my $db = $mgr->connect;
      my $sth = $db->prepare("SELECT userid FROM users WHERE userid=?");
      $sth->execute($userid);
      warn sprintf("userid[%s]Valid_Userid[%s]matches[%s]",
                   $userid,
                   $valid_userid,
                   $userid =~ $valid_userid || "",
                  );
      if ($sth->rows > 0) {
        push @errors, "The userid $userid is already taken.";
      } elsif ($userid !~ $valid_userid) {
        push @errors, "The userid $userid does not match $valid_userid.";
      }
      $sth->finish;
    } else {
      push @errors, "You must supply a desired user-ID\n";
    }
    if ( $PAUSE::Config->{RECAPTCHA_ENABLED} && ! $token ) {
      push @errors, "You must complete the recaptcha to proceed\n";
    }
    if( @errors ) {
      $pause->{errors} = \@errors;
      $showform = 1;
    } else {
      $regOK = 1;
    }
  } else {
    $showform = 1;
  }
  $pause->{showform} = $showform;
  $pause->{reg_ok} = $regOK;

  if ($regOK) {
    if ( $PAUSE::Config->{RECAPTCHA_ENABLED}
        && $c->auto_registration_rate_limit_ok
    ) {
        $pause->{recaptcha_enabled} = 1;
        my ($valid, $err) = $c->verify_recaptcha($token);
        if ( $valid ) {
            # If recaptcha is valid, we shortcut and add the user directly,
            # returning HTML for them to see.
            return $c->_directly_add_user($userid, $fullname);
        }
        elsif ( defined $valid && ! $valid ) {
            die PAUSE::Web::Exception->new(ERROR => "recaptcha failed validation: $err\n");
        }
        # else recapture couldn't complete so continue with normal
        # ID request moderation
    }

    my @to = $mgr->config->mailto_admins;
    push @to, $email;
    $pause->{send_to} = "@to";
    my $time = time;
    if ($rationale) {
      # wrap it
      $rationale =~ s/\r\n/\n/g;
      $rationale =~ s/\r/\n/g;
      my @rat = split /\n\n/, $rationale;
      my $tf = Text::Format->new( bodyIndent => 4, firstIndent => 5);
      $rationale = $tf->paragraphs(@rat);
      $rationale =~ s/^\s{5}/\n    /gm;
    }

    my $session = $c->new_session_counted;
    $session->{APPLY} = {
                         fullname => $fullname,
                         email => $email,
                         homepage => $homepage,
                         userid => $userid,
                         rationale => $rationale,
                        };
    require Data::Dumper; print STDERR "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . Data::Dumper->new([$session->{APPLY}],[qw(APPLY)])->Indent(1)->Useqq(1)->Dump; # XXX
    if (lc($fullname) eq lc($userid)) {
      die PAUSE::Web::Exception->new(ERROR => "fullname looks like spam");
    }
    if (my @x = $rationale =~ /(\.info)/g) {
      die PAUSE::Web::Exception->new(ERROR => "rationale looks like spam") if @x >= 5;
    }
    if (my @x = $rationale =~ m|(http://)|g) {
      die PAUSE::Web::Exception->new(ERROR => "rationale looks like spam") if @x >= 5;
    }
    if ($rationale =~ /interesting/i && $homepage =~ m|http://[^/]+\.cn/.+\.htm$|) {
      die PAUSE::Web::Exception->new(ERROR => "rationale looks like spam");
    }

    $pause->{fullname} = $fullname;
    $pause->{userid}   = $userid;
    $pause->{homepage} = $homepage;
    $pause->{rationale} = $rationale;

    $pause->{session_id} = $c->session_counted_userid;
    my $subject = "PAUSE ID request ($userid; $fullname)";
    my $header = {
          To      => $email,
          Subject => $subject,
          };
    my $blurb = $c->render_to_string("email/public/request_id", format => "email");

    require HTML::Entities;
    my($blurbcopy) = HTML::Entities::encode($blurb,qq{<>&"});
    $blurbcopy =~ s{(
                     https?://
                     [^"'<>\s]+     # arbitrary exclusions, we had \S there,
                                    # but it broke too often
                    )
                   }{<a href=\"$1\">$1</a>}xg;
    $blurbcopy =~ s|(>http.*?)U|$1\n    U|gs; # break the long URL

    $pause->{subject} = $subject;
    $pause->{blurbcopy} = $blurbcopy;

    $header = {
               Subject => $subject
              };
    warn "To[@to]Subject[$header->{Subject}]";
    $mgr->send_mail_multi(\@to,$header,$blurb);
  }
}

sub _directly_add_user {
    my ($c, $userid, $fullname) = @_;
    my $pause = $c->stash(".pause");
    my $mgr = $c->app->pause;
    my $req = $c->req;

    my $T   = time;
    my $dbh = $mgr->connect;
    local ( $dbh->{RaiseError} ) = 0;

    my ( $query, $sth, @qbind );
    my ($email)    = $req->param('pause99_request_id_email');
    my ($homepage) = $req->param('pause99_request_id_homepage');
    $query = qq{INSERT INTO users (
                    userid,     email,    homepage,  fullname,
                     isa_list, introduced, changed,  changedby)
                    VALUES (
                     ?,          ?,        ?,         ?,
                     ?,        ?,          ?,        ?)};
    @qbind =
      ( $userid, "CENSORED", $homepage, $fullname, "", $T, $T, 'RECAPTCHA' );

    # We have a query for INSERT INTO users

    if ( $dbh->do( $query, undef, @qbind ) ) {
        $pause->{added_user} = 1;
        # Not a mailinglist: set and send one time password
        my $onetime = $c->set_onetime_password( $userid, $email );
        $c->send_otp_email( $userid, $email, $onetime );

        # send emails to user and modules@perl.org; latter must censor the
        # user's email address
        my ( $subject, $blurb ) =
          $c->send_welcome_email( [$email], $userid, $email, $fullname, $homepage,
            $fullname );
        $c->send_welcome_email( $PAUSE::Config->{ADMINS},
            $userid, "CENSORED", $fullname, $homepage, $fullname );

        $pause->{subject_for_user_addition} = $subject;
        $pause->{blurb_for_user_addition} = $blurb;

        warn "Info: clearing all fields";
        for my $field (qw(userid fullname email homepage subscribe)) {
            my $param = "pause99_request_id_$field";
            $req->param( $param, "" );
        }
    }
    else {
        warn qq{New user creation failed: [$query] failed. Reason: } . $dbh->errstr;
        # TODO should notify administrators if this occurs
    }
}

1;
