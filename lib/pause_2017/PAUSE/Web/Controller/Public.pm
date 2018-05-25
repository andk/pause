package PAUSE::Web::Controller::Public;

use Mojo::Base "Mojolicious::Controller";
use Time::Duration;

sub mailpw {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my ($param, $email);

  # TUT: We reach this point in the code only if the Querystring
  # specified ACTION=mailpw or something equivalent. The parameter ABRA
  # is used to denote the token that we might have sent them.
  my $abra = $req->param("ABRA") || "";

  # TUT: The parameter pause99_mailpw_1 denotes the userid of the user
  # for whom a password change was requested. Note that anybody has
  # access to that parameter, we do not authentify its origin. Of
  # course not, because that guy says he has lost the password:-) If
  # this parameter is there, we are asked to send a token. Otherwise
  # they only want to see the password-requesting form.
  $param = $req->param("pause99_mailpw_1");
  if ( $param ) {
    $param = uc($param);
    unless ($param =~ /^[A-Z\-]+$/) {
      if ($param =~ /@/) {
        die PAUSE::Web::Exception->new(ERROR =>
                                             qq{Please supply a userid, not an email address.});
      }
      die PAUSE::Web::Exception->new(ERROR =>
                                           qq{A userid of $param is not allowed, please retry with a valid userid. Nothing done.}); # FIXME
    }
    $pause->{mailpw_userid} = $param;

    # TUT: The object $mgr is our knows/is/can-everything object. Here
    # it connects us to the authenticating database
    my $authen_dbh = $mgr->authen_connect;
    my $sql = qq{SELECT *
                 FROM usertable
                 WHERE user = ? };
    my $sth = $authen_dbh->prepare($sql);
    $sth->execute($param);
    my $rec = {};
    if ($sth->rows == 1) {
      $rec = $mgr->fetchrow($sth, "fetchrow_hashref");
    } else {
      my $u;
      eval {
        $u = $c->active_user_record($param);
      };
      if ($@) {
        # FIXME
        die PAUSE::Web::Exception->new(ERROR =>
                                             qq{Cannot find a userid
                                             of $param, please
                                             retry with a valid
                                             userid.});
      } elsif ($u->{userid} && $u->{email}) {
        # this is one of the 94 users (counted on 2005-01-05) that has
        # a users record but no usertable record
        $sql = qq{INSERT INTO usertable (user,secretemail,forcechange,changed)
                                 VALUES (?,   ?,          1,          ?)};

        $authen_dbh->do($sql,{},$u->{userid},$u->{email},time)
            or die PAUSE::Web::Exception->new(ERROR =>
                                                    qq{The userid of $param
 is too old for this interface. Please get in touch with administration.}); # FIXME

        $rec->{secretemail} = $u->{email};
      } else {
        die PAUSE::Web::Exception->new(ERROR =>
                                             qq{A userid of $param
 is not known, please retry with a valid userid.}); # FIXME
      }
    }

    # TUT: all users may have a secret and a public email. We pick what
    # we have.
    unless ($email = $rec->{secretemail}) {
      my $u = $c->active_user_record($param,{hidden_user_ok => 1});
      require YAML::Syck; print STDERR "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . YAML::Syck::Dump({u=>$u}); # XXX

      $email = $u->{email};
    }
    if ($email) {
      $pause->{valid_email} = 1;

      # TUT: Before we insert a record from that table, we remove old
      # entries so the primary key of an old record doesn't block us now.
      $sql = sprintf qq{DELETE FROM abrakadabra
                        WHERE NOW() > expires};
      $authen_dbh->do($sql);

      my $passwd = sprintf "%08x" x 4, rand(0xffffffff), rand(0xffffffff),
          rand(0xffffffff), rand(0xffffffff);
      # warn "pw[$passwd]";
      $pause->{passwd} = $passwd;

      my $then = time + $PAUSE::Config->{ABRA_EXPIRATION};
      $sql = qq{INSERT INTO abrakadabra
                ( user, chpasswd, expires )
                  VALUES
                ( ?, ?, from_unixtime(?) ) };
      local($authen_dbh->{RaiseError}) = 0;
      if ( $authen_dbh->do($sql,undef,$param,$passwd,$then) ) {
      } elsif ($authen_dbh->errstr =~ /Duplicate entry/) {
        my $duration;
        $duration = Time::Duration::duration($PAUSE::Config->{ABRA_EXPIRATION});
        die PAUSE::Web::Exception->new
            (
             ERROR => qq{A token for $param that allows
                  changing of the password has been requested recently
                  (less than $duration ago) and is still valid. Nothing
                  done.}
            );
      } else {
        die PAUSE::Web::Exception->new(ERROR => $authen_dbh->errstr);
      }

      # between Apache::URI and URI::URL
      my $me = $c->my_full_url;  # FIXME
      $me =~ s/^http:/https:/; # do not blindly inherit the schema

      my $mailblurb = $c->render_to_string("email/public/mailpw", format => "email");

      my $header = { Subject => "Your visit at $me" };
      warn "mailto[$email]mailblurb[$mailblurb]";
      $mgr->send_mail_multi([$email], $header, "$mailblurb");
    }
  }
}

sub about {
  my $c = shift;
  $c->serve_pause_doc("04pause.html", "needs_rewrite")
}

sub naming {
  my $c = shift;
  $c->serve_pause_doc("namingmodules.html")
}

sub news {
  my $c = shift;
  $c->serve_pause_doc("index.html")
}

sub history {
  my $c = shift;
  $c->serve_pause_doc("history.html")
}

sub imprint {
  my $c = shift;
  $c->serve_pause_doc("imprint.html")
}

sub operating_model {
  my $c = shift;
  $c->serve_pause_doc("doc/operating-model.md")
}

sub privacy_policy {
  my $c = shift;
  $c->serve_pause_doc("doc/privacy-policy.md")
}

sub pumpkin {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;

  my @hres;
  {
    my $dbh = $mgr->authen_connect;
    my $sth = $dbh->prepare("SELECT user FROM grouptable WHERE ugroup='pumpking' order by user");
    $sth->execute;
    while (my @row = $sth->fetchrow_array) {
      push @hres, $row[0];
    }
    $sth->finish;
  };

  if (my $output_format = $c->req->param("OF")) {
    if ($output_format eq "YAML") {
      return $c->render_yaml(\@hres);
    } else {
      die "not supported OF=$output_format"
    }
  }
  $pause->{pumpkins} = \@hres;
}

sub admin {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;

  my @hres;
  {
    my $dbh = $mgr->authen_connect;
    my $sth = $dbh->prepare("SELECT user FROM grouptable WHERE ugroup='admin' order by user");
    $sth->execute;
    while (my @row = $sth->fetchrow_array) {
      push @hres, $row[0];
    }
    $sth->finish;
  };
  my $output_format = $c->req->param("OF");
  if ($output_format){
    if ($output_format eq "YAML") {
      return $c->render_yaml(\@hres);
    } else {
      die "not supported OF=$output_format"
    }
  }
  $pause->{admins} = \@hres;
}

1;
