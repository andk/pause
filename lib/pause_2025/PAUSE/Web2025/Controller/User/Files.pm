package PAUSE::Web2025::Controller::User::Files;

use Mojo::Base "Mojolicious::Controller";
use HTTP::Date ();
use File::pushd;
use PAUSE ();
use CPAN::DistnameInfo;

sub show {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $u = $c->active_user_record;

  my $dbh = $mgr->connect;
  local($dbh->{RaiseError}) = 0;
  my $userhome = PAUSE::user2dir($u->{userid});
  $pause->{userhome} = $userhome;

  my $pushd = eval { pushd("$PAUSE::Config->{MLROOT}/$userhome") } or return;
  warn "DEBUG: MLROOT[$PAUSE::Config->{MLROOT}] userhome[$userhome] E:M:V[$ExtUtils::Manifest::VERSION]";

  my $time = time;
  my %files = $c->manifind;
  my (%deletes, %whendele, $sth);
  if (
      $sth = $dbh->prepare(qq{SELECT deleteid, changed
                              FROM deletes
                              WHERE deleteid
                              LIKE ?})
      and
      $sth->execute("$userhome/%")
      and
      $sth->rows
     ) {
    my $dhash;
    while ($dhash = $mgr->fetchrow($sth, "fetchrow_hashref")) {
      $dhash->{deleteid} =~ s/\Q$userhome\E\///;
      $deletes{$dhash->{deleteid}}++;
      $whendele{$dhash->{deleteid}} = $dhash->{changed};
    }
  }
  $sth->finish if ref $sth;

  my $indexed = $c->indexed($dbh, $u->{userid});

  foreach my $f (keys %files) {
    unless (stat $f) {
      warn "ALERT: Could not stat f[$f]: $!";
      next;
    }
    my $modified = (stat _)[9];
    my $blurb = $deletes{$f} ?
        $c->scheduled($whendele{$f}) :
            HTTP::Date::time2str($modified);
    $files{$f} = {stat => -s _, blurb => $blurb, indexed => $indexed->{$f}, modified => $modified };
  }
  $pause->{files} = \%files;
}

sub delete {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;

  my $dbh = $mgr->connect;
  local($dbh->{RaiseError}) = 0;
  my $userhome = PAUSE::user2dir($u->{userid});
  $pause->{userhome} = $userhome;

  my $pushd = eval { pushd("$PAUSE::Config->{MLROOT}/$userhome") } or return;
  warn "DEBUG: MLROOT[$PAUSE::Config->{MLROOT}] userhome[$userhome] ExtUtils:Manifest:VERSION[$ExtUtils::Manifest::VERSION]";

  my $time = time;
  my $blurb = "";
  if ($req->param('SUBMIT_pause99_delete_files_delete')) {

    foreach my $f (@{$req->every_param('pause99_delete_files_FILE')}) {
      if ($f =~ m,^/, || $f =~ m,/\.\./,) {
        $blurb .= "WARNING: illegal filename: $userhome/$f\n";
        next;
      }
      unless (-f $f){
        $blurb .= "WARNING: file not found: $userhome/$f\n";
        next;
      }
      if ($f =~ m{ (^|/) CHECKSUMS }x) {
        $blurb .= "WARNING: CHECKSUMS not erasable: $userhome/$f\n";
        next;
      }
      $dbh->do(
        "INSERT INTO deletes VALUES (?, ?, ?)", undef,
        "$userhome/$f", $time, "$pause->{User}{userid}"
      ) or next;

      $blurb .= "\$CPAN/authors/id/$userhome/$f\n";

      # README
      next if $f =~ /\.readme$/;
      my $readme = $f;
      $readme =~ s/(\.tar.gz|\.zip)$/.readme/;
      if ($readme ne $f && -f $readme) {
        $dbh->do(
          q{INSERT INTO deletes VALUES (?,?,?)}, undef,
          "$userhome/$readme", $time, $pause->{User}{userid},
        ) or next;
        $blurb .= "\$CPAN/authors/id/$userhome/$readme\n";
      }
    }
  } elsif ($req->param('SUBMIT_pause99_delete_files_undelete')) {
    foreach my $f (@{$req->every_param('pause99_delete_files_FILE')}) {
      my $sql = "DELETE FROM deletes WHERE deleteid = ?";
      $dbh->do(
        $sql, undef,
        "$userhome/$f"
      ) or warn sprintf "FAILED Query: %s/: %s", $sql, "$userhome/$f", $DBI::errstr;
    }
  }

  if ($blurb) {
    $pause->{blurb} = $blurb;
    $blurb = $c->render_to_string("email/user/delete_files", format => "email");

    my %umailset;
    my $name = $u->{asciiname} || $u->{fullname} || "";
    my $Uname = $pause->{User}{asciiname} || $pause->{User}{fullname} || "";
    if ($u->{secretemail}) {
      $umailset{qq{"$name" <$u->{secretemail}>}} = 1;
    } elsif ($u->{email}) {
      $umailset{qq{"$name" <$u->{email}>}} = 1;
    }
    if ($u->{userid} ne $pause->{User}{userid}) {
      if ($pause->{User}{secretemail}) {
        $umailset{qq{"$Uname" <$pause->{User}{secretemail}>}} = 1;
      }elsif ($pause->{User}{email}) {
        $umailset{qq{"$Uname" <$pause->{User}{email}>}} = 1;
      }
    }
    $umailset{$PAUSE::Config->{ADMIN}} = 1;
    my @to = keys %umailset;
    my $header = {
                  Subject => "Files of $u->{userid} scheduled for deletion"
                 };
    $mgr->send_mail_multi(\@to, $header, $blurb);
  }

  my %files = $c->manifind;
  my (%deletes, %whendele, $sth);
  if (
      $sth = $dbh->prepare(qq{SELECT deleteid, changed
                              FROM deletes
                              WHERE deleteid
                              LIKE ?})           #}
      and
      $sth->execute("$userhome/%")
      and
      $sth->rows
     ) {
    my $dhash;
    while ($dhash = $mgr->fetchrow($sth, "fetchrow_hashref")) {
      $dhash->{deleteid} =~ s/\Q$userhome\E\///;
      $deletes{$dhash->{deleteid}}++;
      $whendele{$dhash->{deleteid}} = $dhash->{changed};
    }
  }
  $sth->finish if ref $sth;

  my $indexed = $c->indexed($dbh, $u->{userid});

  foreach my $f (keys %files) {
    unless (stat $f) {
      warn "ALERT: Could not stat f[$f]: $!";
      next;
    }
    my $tmpf = $f;
    $tmpf =~ s/\.(?:readme|meta)$/.tar.gz/;
    my $info = CPAN::DistnameInfo->new($tmpf);
    my $distv = $info->distvname;
    my $modified = (stat _)[9];
    my $blurb = $deletes{$f} ?
        $c->scheduled($whendele{$f}) :
            HTTP::Date::time2str($modified);
    $files{$f} = {stat => -s _, blurb => $blurb, indexed => $indexed->{$f}, distv => $distv, modified => $modified };
    $pause->{deleting_indexed_files} = 1 if $deletes{$f} && $indexed->{$f};
  }
  $pause->{files} = \%files;
}

sub scheduled {
  my ($c, $when) = @_;
  my $time = time;
  my $expires = $when + ($PAUSE::Config->{DELETES_EXPIRE}
                         || 60*60*24*2);
  my $return = "Scheduled for deletion \(";
  $return .= $time < $expires ? "due at " : "already expired at ";
  $return .= HTTP::Date::time2str($expires);
  $return .= "\)";
  $return;
}

sub indexed {
  my ($c, $dbh, $userid) = @_;

  my %indexed;
  my $sth;
  if ($sth = $dbh->prepare(qq{SELECT distinct(packages.dist) AS dist FROM packages JOIN uris ON packages.dist = uris.uriid WHERE packages.status = ? AND uris.userid = ?})
    and
    $sth->execute('index', $userid)
    and
    $sth->rows
  ) {
    require CPAN::DistnameInfo;
    my $dist;
    while(($dist) = $sth->fetchrow_array) {
      my $file = CPAN::DistnameInfo->new($dist)->filename or next;
      $indexed{$file} = 1;
    }
  }
  $sth->finish if ref $sth;
  return \%indexed;
}

1;
