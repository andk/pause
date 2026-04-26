package PAUSE::API::Controller::Upload;

use Mojo::Base "Mojolicious::Controller";
use Mojo::ByteStream;
use Mojo::URL;
use File::pushd;

sub upload {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $token_info = $pause->{token_info} || {};
  my $scope = $token_info->{scope};

  # TODO: finer control
  die PAUSE::Web::Exception->new(ERROR => 'Invalid scope') unless $scope eq 'upload';

  $PAUSE::Config->{INCOMING_LOC} =~ s|/$||;

  my $userid = uc $pause->{token_info}{user};
  my $userhome = PAUSE::user2dir($userid);

  my $upl = $req->upload('file');
  unless ($upl->size) {
    return $c->render(json => {error => 'Empty file'}, status => 400);
  }

  my $uri;
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
    die PAUSE::Web::Exception->new(ERROR => "Couldn't copy file '$filename' to '$to': $!");
  }
  unless ($upl->filename eq $filename) {
    require Dumpvalue;
    my $dv = Dumpvalue->new;
    $pause->{upload_is_renamed} = {
      from => $dv->stringify($upl->filename),
      to => $dv->stringify($filename),
    };
  }
  my $dbh = $mgr->connect;
  my $now = time;
  my $server = $PAUSE::Config->{SERVER_NAME} || $req->url->to_abs->host;

    eval { Mojo::URL->new("$PAUSE::Config->{INCOMING}/$uri") };
    if ($@) {
      $pause->{invalid_uri} = 1;
      # FIXME
      die PAUSE::Web::Exception
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
        die PAUSE::Web::Exception
            ->new(ERROR => "Files with the name CHECKSUMS cannot be
                            uploaded to CPAN, they are reserved for
                            CPAN's internals.");

      }
      my $subdir = "";
      if ( $req->param("subdir") ) {
        $subdir = $req->param("subdir");
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
        die PAUSE::Web::Exception
            ->new(ERROR => "Path name too long: $uriid is longer than 255 characters.");
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
        $uriid, $userid, $filename, $uri, $pause->{User}{userid}, $now,
    $is_perl6
      );
      #display query
      local($dbh->{RaiseError}) = 0;
      if ($dbh->do($query, undef, @query_params)) {
        return $c->render(json => {result => 'Upload succeeded'}, status => 200);
      } else {
        my $errmsg = $dbh->errstr;
        if ($errmsg =~ /non\s+unique\s+key|Duplicate/i) {
          return $c->render(json => {error => 'Duplicated'}, status => 409);
        }
        return $c->render(json => {error => 'Not accepted'}, status => 406);
      }
    }
}

1;
