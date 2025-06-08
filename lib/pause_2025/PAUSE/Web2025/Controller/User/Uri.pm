package PAUSE::Web2025::Controller::User::Uri;

use Mojo::Base "Mojolicious::Controller";
use Mojo::ByteStream;
use Mojo::URL;
use File::pushd;

sub add {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  $PAUSE::Config->{INCOMING_LOC} =~ s|/$||;

  my $u = $c->active_user_record;
  die PAUSE::Web2025::Exception
      ->new(ERROR =>
            "Unidentified error happened, please write to the PAUSE admins
 at $PAUSE::Config->{ADMIN} and help them identifying what's going on. Thanks!")
          unless $u->{userid};

  my($tryupload) = 1; # everyone supports multipart now
  my($uri);
  my $userhome = PAUSE::user2dir($u->{userid});

  if ($req->param("SUBMIT_pause99_add_uri_HTTPUPLOAD")
      || $req->param("SUBMIT_pause99_add_uri_httpupload")) {
    my $upl = $req->upload('pause99_add_uri_httpupload');
    unless ($upl->size) {
      warn "Warning: maybe they hit RETURN, no upload size, not doing HTTPUPLOAD";
      $req->param("SUBMIT_pause99_add_uri_HTTPUPLOAD","");
      $req->param("SUBMIT_pause99_add_uri_httpupload","");
    }
  }
  if (!   $req->param("SUBMIT_pause99_add_uri_HTTPUPLOAD")
      &&! $req->param("SUBMIT_pause99_add_uri_httpupload")
      &&! $req->param("SUBMIT_pause99_add_uri_uri")
      &&! $req->param("SUBMIT_pause99_add_uri_upload")
     ) {
    # no submit button
    if ($req->param("pause99_add_uri_uri")) {
      $req->param("SUBMIT_pause99_add_uri_uri", "2ndguess");
    } elsif ($req->param("pause99_add_uri_upload")) {
      $req->param("SUBMIT_pause99_add_uri_upload", "2ndguess");
    }
  }

  my $didit = 0;
  my $now = time;
  if (
      $req->param("SUBMIT_pause99_add_uri_httpupload") || # from 990806
      $req->param("SUBMIT_pause99_add_uri_HTTPUPLOAD")
     ) {
    { # $pause->{UseModuleSet} eq "ApReq"
      my $upl;
      if (
          $upl = $req->upload("pause99_add_uri_httpupload") or # from 990806
          $upl = $req->upload("HTTPUPLOAD")
         ) {
        if ($upl->size) {
          my $filename = $upl->filename;
          $filename =~ s(.*/)()gs;      # no slash
          $filename =~ s(.*\\)()gs;     # no backslash
          $filename =~ s(.*:)()gs;      # no colon
          $filename =~ s/[^A-Za-z0-9_\-\.\@\+]//g; # only ASCII-\w and - . @ + allowed
          my $to = "$PAUSE::Config->{INCOMING_LOC}/$filename";
          # my $fhi = $upl->fh;
          if (-f $to && -s _ == 0) { # zero sized files are a common problem
            unlink $to;
          }
          if ($upl->move_to($to)){
            $uri = $filename;
            # Got an empty $to in the HTML page, so for debugging..
            $pause->{successfully_copied_to} = $to;
            warn "h1[File successfully copied to '$to']filename[$filename]";
          } else {
            die PAUSE::Web2025::Exception
                ->new(ERROR =>
                      "Couldn't copy file '$filename' to '$to': $!");
          }
          unless ($upl->filename eq $filename) {

            require Dumpvalue;
            my $dv = Dumpvalue->new;
            $req->param("pause99_add_uri_httpupload",$filename);
            $pause->{upload_is_renamed} = {
              from => $dv->stringify($upl->filename),
              to => $dv->stringify($filename),
            };
          }
        } else {
          die PAUSE::Web2025::Exception
              ->new(ERROR =>
                    "uploaded file was zero sized");
        }
      } else {
        die PAUSE::Web2025::Exception
            ->new(ERROR =>
                  "Could not create an upload object. DEBUG: upl[$upl]");
      }
    }
  } elsif ( $req->param("SUBMIT_pause99_add_uri_uri") ) {
    $uri = $req->param("pause99_add_uri_uri");
    $req->param("pause99_add_uri_httpupload",""); # I saw spurious
                                                  # nonsense in the
                                                  # field that broke
                                                  # XHTML
  } elsif ( $req->param("SUBMIT_pause99_add_uri_upload") ) {
    $uri = $req->param("pause99_add_uri_upload");
    $req->param("pause99_add_uri_httpupload",""); # I saw spurious
                                                  # nonsense in the
                                                  # field that broke
                                                  # XHTML
  }
  my $server = $PAUSE::Config->{SERVER_NAME} || $req->url->to_abs->host;
  my $dbh = $mgr->connect;

  $pause->{uploaded_uri} = $uri;
  if ($uri) {
    $c->add_uri_continue_with_uri($uri,\$didit);
  }

  if ($tryupload) {
    $pause->{tryupload} = $tryupload;
    my $subdirs = $c->_find_subdirs($u);
    $pause->{subdirs} = $subdirs if $subdirs;
  }

  # HTTP UPLOAD

  if ($tryupload) {
    $c->need_form_data(1);
    $c->res->headers->accept("*");
  }

  # via FTP GET

  warn "DEBUG: UPLOAD[$PAUSE::Config->{UPLOAD}]";

  # END OF UPLOAD OPTIONS
}

sub _find_subdirs {
  my ($c, $u) = @_;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;

  my $userhome = PAUSE::user2dir($u->{userid});
  $pause->{userhome} = $userhome;

  my $pushd = eval { pushd("$PAUSE::Config->{MLROOT}/$userhome") } or return;
  warn "DEBUG: MLROOT[$PAUSE::Config->{MLROOT}] userhome[$userhome] E:M:V[$ExtUtils::Manifest::VERSION]";

  my %files = $c->manifind;
  my %seen;
  my @dirs = sort grep !$seen{$_}++, grep s|(.+)/[^/]+|$1|, keys %files;
  return unless @dirs;
  unshift @dirs, ".";
  return \@dirs;
}

sub add_uri_continue_with_uri {
  my ($c, $uri, $didit) = @_;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;
  my $userhome = PAUSE::user2dir($u->{userid});
  my $dbh = $mgr->connect;
  my $now = time;
  my $server = $PAUSE::Config->{SERVER_NAME} || $req->url->to_abs->host;

    eval { Mojo::URL->new("$PAUSE::Config->{INCOMING}/$uri") };
    if ($@) {
      $pause->{invalid_uri} = 1;
      # FIXME
      die PAUSE::Web2025::Exception
          ->new(ERROR => [Mojo::ByteStream->new(qq{
Sorry, <b>$uri</b> could not be recognized as an uri (}),
                          $@,
                         Mojo::ByteStream->new(qq{\)Please
try again or report errors to <a href="mailto:}),
                          $PAUSE::Config->{ADMIN},
                          Mojo::ByteStream->new(qq{">the administrator</a></p>})]);
    } else {
      require LWP::UserAgent;
      my $ua = LWP::UserAgent->new;
      $ua->timeout($PAUSE::Config->{TIMEOUT}) if $PAUSE::Config->{TIMEOUT};
      my $res = $ua->head($uri);
      my $filename = $res && $res->is_success ? $res->filename : undef;
      $filename ||= $uri; # as a last resort
      $filename =~ s,.*/,, ;
      $filename =~ s/[^A-Za-z0-9_\-\.\@\+]//g; # only ASCII-\w and - . @ + allowed

      if ($filename eq "CHECKSUMS") {
        # userid DERHAAG demonstrated that it could be uploaded on 2002-04-26
        die PAUSE::Web2025::Exception
            ->new(ERROR => "Files with the name CHECKSUMS cannot be
                            uploaded to CPAN, they are reserved for
                            CPAN's internals.");

      }
      my $subdir = "";
      if ( $req->param("pause99_add_uri_subdirtext") ) {
        $subdir = $req->param("pause99_add_uri_subdirtext");
      } elsif ( $req->param("pause99_add_uri_subdirscrl") ) {
        $subdir = $req->param("pause99_add_uri_subdirscrl");
      }

      my $uriid = "$userhome/$filename";

      if (defined $subdir && length $subdir) {
        # disallowing . to make /./ and /../ handling easier
        $subdir =~ s|[^A-Za-z0-9_\-\@\+/]||g; # as above minus "." plus "/"
        $subdir =~ s|^/+||;
        $subdir =~ s|/$||;
        $subdir =~ s|/+|/|g;
      }
      my $is_perl6 = 0;
      if (defined $subdir && length $subdir) {
        $is_perl6 = 1 if $subdir =~ /^Perl6\b/;
        $uriid = "$userhome/$subdir/$filename";
      }

      if ( length $uriid > 255 ) {
        die PAUSE::Web2025::Exception
            ->new(ERROR => "Path name too long: $uriid is longer than
                255 characters.");
      }

    ALLOW_OVERWRITE: if (PAUSE::may_overwrite_file($filename)) {
        $dbh->do("DELETE FROM uris WHERE uriid = ?", undef, $uriid);
      }

      my $query = q{INSERT INTO uris
                            (uriid,     userid,
                             basename,
                             uri,
                             changedby, changed, is_perl6)
                     VALUES (?, ?, ?, ?, ?, ?, ?)};
      my @query_params = (
        $uriid, $u->{userid}, $filename, $uri, $pause->{User}{userid}, $now,
    $is_perl6
      );
      #display query
      local($dbh->{RaiseError}) = 0;
      if ($dbh->do($query, undef, @query_params)) {
        $$didit = 1;
        $pause->{query_succeeded} = 1;

        my $usrdir = "https://$server/pub/PAUSE/authors/id/$userhome";
        my $tailurl = $c->my_full_url(ACTION => 'tail_logfile')->query(pause99_tail_logfile_1 => 5000);

        $pause->{usrdir} = $usrdir;
        $pause->{tailurl} = $tailurl;
      } else {
        my $errmsg = $dbh->errstr;
        $pause->{errmsg} = $errmsg;
        $c->res->code(406);

        if ($errmsg =~ /non\s+unique\s+key|Duplicate/i) {
          $pause->{duplicate} = 1;
          $c->res->code(409);
          my $sth = $dbh->prepare("SELECT * FROM uris WHERE uriid=?");
          $sth->execute($uriid);
          my $rec = $mgr->fetchrow($sth, "fetchrow_hashref");
          for my $k (qw(changed dgot dverified)) {
            if ($rec->{$k}) {
              $rec->{$k} .= sprintf " [%s UTC]", scalar gmtime $rec->{$k};
            }
          }
          $pause->{rec} = $rec;
        }
      }
    }
}

1;
