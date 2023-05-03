use strict;
use warnings;
package PAUSE::dist;
use vars qw(%CHECKSUMDONE $AUTOLOAD);

use Email::Sender::Simple qw(sendmail);
use File::Copy ();
use List::MoreUtils ();
use PAUSE ();
use Parse::CPAN::Meta;
use PAUSE::mldistwatch::Constants;
use PAUSE::Indexer::Errors;
use JSON::XS ();

use PAUSE::Logger '$Logger';

sub DESTROY {}

sub new {
  my($me) = shift;
  my $self = bless { @_ }, ref($me) || $me;
  $self->{USERID} = PAUSE::dir2user($self->{DIST});
  $self->{TIME}   = time;

  return $self;
}

sub hub { $_[0]{HUB} }

sub ignoredist {
  my $self = shift;
  my $dist = $self->{DIST};
  if ($dist =~ m|/\.|) {
    $Logger->log("Warning: illegal filename");
    return 1;
  }

  return "non-dist file" if $dist =~ /(\.readme|\.sig|\.meta|CHECKSUMS)$/;

  # Stupid to have code that needs to be maintained in two places,
  # here and in edit.pm:
  return "weird CNANDOR case"
    if $dist =~ m!CNANDOR/(?:mp_(?:app|debug|doc|lib|source|tool)|VISEICat(?:\.idx)?|VISEData)!;

  return;
}

sub normalize_package_casing {
  my ($self) = @_;

  for my $lc_package (keys %{ $self->{CHECKINS} }) {
    my %pkg_checkins = %{ $self->{CHECKINS}{$lc_package} };

    my (@forms) = sort keys %pkg_checkins;

    if (@forms == 1) {
      $Logger->log("ensuring canonicalized case of $forms[0]");
      $self->hub->permissions->canonicalize_module_casing($forms[0]);
      next;
    }

    $Logger->log([
      "case conflict resolved by LAST-RESORT: %s -> %s",
      \@forms,
      $forms[0],
    ]);
    my $form = $forms[0];
    $self->hub->permissions->canonicalize_module_casing($forms[0]);
  }
}

sub delete_goner {
  my $self = shift;
  my $dist = $self->{DIST};
  if ($self->hub->{PICK} && $self->hub->{PICK}{$dist}) {
    $Logger->log("Warning: parameter pick [$dist] refers to a goner, ignoring");
    return;
  }
  my $dbh = $self->connect;
  $dbh->do("DELETE FROM packages WHERE dist=?", undef, $dist);
  $dbh->do("DELETE FROM distmtimes WHERE dist=?", undef, $dist);
}

sub writechecksum {
  no warnings 'once';
  my($self, $dir) = @_;
  return if $CHECKSUMDONE{$dir}++;
  return unless IPC::Cmd::can_run( $PAUSE::Config->{CHECKSUMS_SIGNING_PROGRAM} );
  local($CPAN::Checksums::CAUTION) = 1;
  local($CPAN::Checksums::SIGNING_PROGRAM) =
    $PAUSE::Config->{CHECKSUMS_SIGNING_PROGRAM} . " " .
    $PAUSE::Config->{CHECKSUMS_SIGNING_ARGS};
  local($CPAN::Checksums::SIGNING_KEY) =
    $PAUSE::Config->{CHECKSUMS_SIGNING_KEY};

  unless (eval { CPAN::Checksums::updatedir($dir, $self->mlroot); 1 }) {
    my $error = $@;
    $Logger->log([ "CPAN::Checksums::updatedir died with error: %s", $error ]);
    return; # a die might cause even more trouble
  }

  return unless -e "$dir/CHECKSUMS"; # e.g. only files-to-ignore
  PAUSE::newfile_hook("$dir/CHECKSUMS");
}

sub mtime_ok {
  my $self = shift;
  my $otherts = shift || 0;
  my $dist = $self->{DIST};
  my $dbh = $self->connect;
  unless ($otherts){ # positive $otherts means it was alive last time
    # Hahaha: he didn't think of the programmer who wants to
    # introduce locking:
    # $dbh->do("DELETE FROM distmtimes WHERE dist=?", undef, $dist);

    local($dbh->{RaiseError}) = 0;
    # this may fail if we have a race condition, but we'll
    # decide later if this is the case:
    $dbh->do("INSERT INTO distmtimes (dist) VALUES (?)", undef, $dist);
  }
  my $MLROOT = $self->mlroot;
  my $mtime = (stat "$MLROOT/$dist")[9];
  my $dirname = File::Basename::dirname("$MLROOT/$dist");
  my $checksumtime = (stat "$dirname/CHECKSUMS")[9] || 0;

  if ($mtime) {
    # ftp-mirroring can send us up to one day old files
    my $sane_checksumtime = $mtime + 86400;
    if ($sane_checksumtime > $checksumtime) {
      $self->writechecksum($dirname); # may do nothing
      $checksumtime = (stat "$dirname/CHECKSUMS")[9] || 0;
      if ($sane_checksumtime > $checksumtime # still too old
        &&
        time > $sane_checksumtime          # and now in the past
      ) {
        utime(
          $sane_checksumtime,
          $sane_checksumtime,
          "$dirname/CHECKSUMS",
        );
      }
    }
    if ($mtime > $otherts) {
      $dbh->do(
        qq{UPDATE distmtimes SET distmtime=?, distmdatetime=? WHERE dist=?},
        undef,
        $mtime,
        PAUSE->_time_string($mtime),
        $dist,
      );
      $Logger->log("assigned mtime $mtime");
      return 1;
    }
  }
  if ($self->hub->{PICK}{$dist}) {
    return 1;
  }
  return;
}

sub untar {
  my ($self, $ctx) = @_;
  my $dist = $self->{DIST};
  local *TARTEST;
  my $tarbin = $self->hub->{TARBIN};
  my $MLROOT = $self->mlroot;
  my $tar_opt = "tzf";
  if ($dist =~ /\.(?:tar\.bz2|tbz)$/) {
    $tar_opt = "tjf";
  }
  open TARTEST, "$tarbin $tar_opt $MLROOT/$dist |";
  while (<TARTEST>) {
    if (m:^\.\./: || m:/\.\./: ) {
      $Logger->log("*** ALERT: updir detected!");
      $ctx->alert("updir detected!");
      $self->{COULD_NOT_UNTAR}++;
      return;
    }
    if (m:^[^/]+/META6\.json$:m) {
        $self->{PERL_MAJOR_VERSION} = 6
    }
  }
  $self->{PERL_MAJOR_VERSION} = 5 unless defined $self->{PERL_MAJOR_VERSION};
  unless (close TARTEST) {
    $Logger->log("could not untar $dist!");
    $ctx->alert("could not untar!");
    $self->{COULD_NOT_UNTAR}++;
    return;
  }
  $tar_opt = "xzf";
  if ($dist =~ /\.(?:tar\.bz2|tbz)$/) {
    $tar_opt = "xjf";
  }

  my @cmd = ($tarbin, $tar_opt, "$MLROOT/$dist");
  $Logger->log([ "going to untar with: %s", \@cmd ]);

  unless (system(@cmd)==0) {
    $Logger->log([
      "re-trying untar with -v; the first try failed: %s",
      Process::Status->as_struct,
    ]);

    $cmd[1] = "v$tar_opt";
    unless (system(@cmd)==0) {
      $Logger->log([
        "re-try of untar with -v failed, too: %s",
        Process::Status->as_struct,
      ]);

      return;
    }
  }

  $Logger->log("untarred $MLROOT/$dist");
  return 1;
}

sub perl_major_version { shift->{PERL_MAJOR_VERSION} }

# Commented out this function just like $ISA_BLEAD_PERL
##sub isa_blead_perl {
##  my($self,$dist) = @_;
##  scalar $dist =~ /$PAUSE::dist::ISA_BLEAD_PERL/;
##}

# should use CPAN::DistnameInfo but note: "zip" not contained
# because it is special-cased below
my $SUFFQR = qr/\.(tgz|tbz|tar[\._-]gz|tar\.bz2|tar\.Z)$/;

sub _examine_regular_perl {
  my ($self, $ctx) = @_;
  my ($suffix, $skip);

  my $dist = $self->{DIST};

  my($u) = PAUSE::dir2user($dist); # =~ /([A-Z][^\/]+)/; # XXX dist2user

  my $has_pumpking_bit = PAUSE->user_has_pumpking_bit($u);

  if ($has_pumpking_bit){
    $skip = 0;
    $Logger->log("perl dist from trusted user $u");
  } else {
    $skip = 1;
    $Logger->log("*** ALERT: perl dist $dist from untrusted user $u; skip set to [$skip]");
  }

  if ($dist =~ $SUFFQR) {
    $suffix = $1;
  } else {
    $Logger->log("perl distro ($dist) with an unusual suffix!");
    $ctx->alert("perl distro ($dist) with an unusual suffix!");
  }

  unless ($skip) {
    $skip = 1 unless $self->untar($ctx);
  }

  return ($suffix, $skip);
}

sub isa_dev_version {
  my ($self) = @_;
  my $dist = $self->{DIST};

  return $dist =~ /\d\.\d+_\d/ || $dist =~ /-TRIAL[0-9]*$SUFFQR/;
}

sub examine_dist {
  my ($self, $ctx) = @_;
  my $dist = $self->{DIST};
  my $MLROOT = $self->mlroot;
  my($suffix,$skip);
  $suffix = $skip = "";

  if (PAUSE::isa_regular_perl($dist)) {
    ($suffix, $skip) = $self->_examine_regular_perl($ctx);

    $self->{SUFFIX} = $suffix;

    if ($skip) {
      $ctx->abort_indexing_dist("won't process regular perl upload");
    }

    return;
  }

  if ($self->isa_dev_version) {
    $self->{SUFFIX} = "N/A";
    $ctx->abort_indexing_dist("dist is a developer release");
  }

  if ($dist =~ m|/perl-\d+|) {
    $self->{SUFFIX} = "N/A";
    $ctx->abort_indexing_dist("dist is an unofficial perl-like release");
  }

  if ($dist =~ $SUFFQR) {
    $self->{SUFFIX} = $1;
    unless ($self->untar($ctx)) {
      $ctx->abort_indexing_dist("can't untar archive");
    }
  } elsif ($dist =~ /\.pm\.(?:Z|gz|bz2)$/) {
    $self->{SUFFIX} = "N/A";
    $ctx->abort_indexing_dist(DISTERROR('single_pm'));
  } elsif ($dist =~ /\.zip$/) {
    $self->{SUFFIX} = "zip";
    my $unzipbin = $self->hub->{UNZIPBIN};
    my $system = "$unzipbin $MLROOT/$dist > /dev/null 2>&1";
    unless (system($system)==0) {
      $Logger->log([
        "error occured while unzipping: %s",
        Process::Status->as_struct,
      ]);

      # XXX Temporarily disabled -- rjbs, 2019-04-27
      # system("$unzipbin -t $MLROOT/$dist");
    }
  } else {
    $ctx->abort_indexing_dist("file does not appear to be a CPAN distribution");
  }

  return;
}

sub connect {
  my($self) = @_;
  return $self->hub->connect;
}

sub disconnect {
  my($self) = @_;
  return $self->hub->disconnect;
}

sub mlroot {
  my($self) = @_;
  $self->hub->mlroot;
}

sub _update_mail_content_when_things_were_indexed {
    my ($self, $ctx, $statuses, $m_ref, $status_ref) = @_;

    my $Lstatus = 0;
    my $intro_written;

    my $successes = grep {; $_->{is_success} } @$statuses;

    unless (defined $$status_ref) {
      $$status_ref  = $successes == @$statuses  ? "OK"
                    : $successes                ? "partially successful"
                    :                             "Failed";

      push @$m_ref, "Status of this distro: $$status_ref\n";
      push @$m_ref, "="x(length($$status_ref)+23), "\n\n";
    }

    push @$m_ref, qq{\nThe following packages have been found in the distro:\n\n};

    my $tf14 = Text::Format->new(
      bodyIndent  => 14,
      firstIndent => 14,
    );

    my $last_header = q{};

    for my $status (
      # First failures, grouped, then success, by description.
      sort { $b->{is_success} <=> $a->{is_success}
          || $a->{header} cmp $b->{header} } @$statuses
    ) {
      my $header = $status->{header};

      unless ($header eq $last_header) {
        push @$m_ref, "## $header\n\n";
        $last_header = $header;
      }

      push @$m_ref, sprintf("     package: %s\n",  $status->{package});

      if (my @warnings = $ctx->warnings_for_package($status->{package})) {
        push @$m_ref, map {;
               sprintf("     WARNING: %s\n", $_->{text}) } @warnings;
      }

      my $body = $tf14->format($status->{body});
      $body =~ s/\A\s+//; # The first line is indented by the leading text!

      my $file = $status->{filename} // "missing in META, tolerated by PAUSE indexer";

      push @$m_ref, sprintf("     version: %s\n", $status->{version});
      push @$m_ref, sprintf("     in file: %s\n", $file);
      push @$m_ref, sprintf("     status : %s\n", $body);
    }
}

sub _update_mail_content_when_nothing_was_indexed {
    my ($self, $ctx, $m_ref, $status_ref) = @_;

    if ($self->version_from_meta_ok($ctx)) {
      push @$m_ref,  qq{Nothing in this distro has been \n}
                  .  qq{indexed, because according to META.yml this\n}
                  .  qq{package does not provide any modules.\n\n};

      $$status_ref = "Empty_provides";
    } else {
      push @$m_ref,  qq{No or no indexable package statements could be found\n}
                  .  qq{in the distro (maybe a script or documentation\n}
                  .  qq{distribution or a developer release?)\n\n};

      $$status_ref = "Empty_no_pm";
    }
}

sub mail_summary {
  my ($self, $ctx) = @_;
  my $distro = $self->{DIST};
  my $author = $self->{USERID};
  my @m;

  push @m,
    "The following report has been written by the PAUSE namespace indexer.\n",
    "Please contact modules\@perl.org if there are any open questions.\n";

  if ($ctx->warnings_for_all_packages) {
    # If there were any warnings, put in a note to the reader that they should
    # look for them.
    push @m,
      "\nWARNING:  Some irregularities were found while indexing your\n",
        "          distribution.  See below for more details.\n";
  }

  my $time = gmtime;
  my $MLROOT = $self->mlroot;
  my $mtime = gmtime((stat "$MLROOT/$distro")[9]);
  my $nfiles = scalar @{ $self->{MANIFOUND} // [] };
  my $pmfiles = grep /\.pm$/, @{$self->{MANIFOUND}};
  my $dbh = $self->connect;
  my $sth = $dbh->prepare("SELECT asciiname, fullname
    FROM   users
    WHERE userid=?");
  $sth->execute($author);
  my($u) = $sth->fetchrow_hashref;
  my $asciiname = $u->{asciiname} // $u->{fullname} // "name unknown";
  my $substrdistro = substr $distro, 5;
  my($distrobasename) = $substrdistro =~ m|.*/(.*)|;
  my $versions_from_meta = $self->version_from_meta_ok($ctx) ? "yes" : "no";
  my $parse_cpan_meta_version = Parse::CPAN::Meta->VERSION;

  # This can occur when, for example, the "distribution" is Foo.pm.gz — of
  # course then there is no README or META.*! -- rjbs, 2014-03-15
  # ...but we banned bare .pm files in 2013, so what's this really about?
  # I think it's plain old "no README file included".
  # -- rjbs, 2018-04-19
  my $readme   = $self->{README}   // "(none)";
  my $metafile = $self->{METAFILE} // "(none)";

  push @m, qq[
  User: $author ($asciiname)
  Distribution file: $distrobasename
  Number of files: $nfiles
  *.pm files: $pmfiles
  README: $readme
  META-File: $metafile
  META-Parser: Parse::CPAN::Meta $parse_cpan_meta_version
  META-driven index: $versions_from_meta
  Timestamp of file: $mtime UTC
  Time of this run: $time UTC\n\n];
  my $tf = Text::Format->new(firstIndent=>0);

  my $status_over_all;

  my @dist_errors = $ctx->dist_errors;

  for my $error (@dist_errors) {
    my $header = $error->{header};
    my $body   = $error->{body};
    $body = $body->($self) if ref $body;

    push @m, "## $header\n\n";
    push @m, $tf->format($body), qq{\n\n};

    $status_over_all = "Failed";
  }

  if (($status_over_all//'Ok') ne 'Failed') {
    my @statuses = $ctx->package_statuses;

    if (@statuses) {
      $self->_update_mail_content_when_things_were_indexed(
        $ctx,
        \@statuses,
        \@m,
        \$status_over_all,
      );
    } else {

      # No files have status, no dist-wide errors.  Nothing to report!
      return unless $pmfiles || $ctx->dist_errors;

      $self->_update_mail_content_when_nothing_was_indexed(
        $ctx,
        \@m,
        \$status_over_all,
      );
    }
  }

  push @m, qq{__END__\n};

  $self->_send_email(\@m, $status_over_all);
  return;
}

sub _send_email {
    my ($self, $lines, $status_over_all) = @_;

    if ($PAUSE::Config->{TESTHOST} || $self->hub->{OPT}{testhost}) {
      if ($self->hub->{PICK}) {
        local $"="";
        warn "Unsent Report [@$lines]";
      }

      return;
    }

    my $author = $self->{USERID};
    my $distro = $self->{DIST};

    my $substrdistro = substr $distro, 5;

    my $pma = PAUSE::MailAddress->new_from_userid($author);
    my $to = sprintf "%s, %s", $pma->address, $PAUSE::Config->{ADMIN};
    my $failed = "";

    if ($status_over_all ne "OK") {
      $failed = "Failed: ";
    }

    my $email = Email::MIME->create(
        header_str => [
            To      => $to,
            Subject => $failed."PAUSE indexer report $substrdistro",
            From    => "PAUSE <$PAUSE::Config->{UPLOAD}>",
        ],
        attributes => {
          charset      => 'utf-8',
          content_type => 'text/plain',
          encoding     => 'quoted-printable',
        },
        body_str => join(q{}, @$lines),
    );

    sendmail($email);

    $Logger->log("sent indexer report email");
}

sub check_blib {
  my ($self, $ctx) = @_;
  if (grep m|^[^/]+/blib/|, @{$self->{MANIFOUND}}) {
    $self->{HAS_BLIB}++;
    $ctx->abort_indexing_dist(DISTERROR('blib'));
  }
  # sometimes they package their stuff deep inside a hierarchy
  my @found = @{$self->{MANIFOUND}};
  my $endless = 0;
  DIRDOWN: while () {
    # step down directories as long as possible
    my %seen;
    my @top = grep { s|/.*||; !$seen{$_}++ } map { $_ } @found;
    if (@top == 1) {
      # print $top[0];
      my $success = 0;
      for (@found){ # note, we modify found, not top!
        s|\Q$top[0]\E/|| && $success++;
      }
      last DIRDOWN unless $success; # no directory to step down anymore
      if (++$endless > 10) {
        $ctx->alert("ENDLESS LOOP detected!");
        last DIRDOWN;
      }
      next DIRDOWN;
    }
    # more than one entry in this directory means final check
    if (grep m|^blib/|, @found) {
      $self->{HAS_BLIB}++;
      $ctx->abort_indexing_dist(DISTERROR('blib'));
    }
    last DIRDOWN;
  }
}

sub check_multiple_root {
  my ($self, $ctx) = @_;
  my %seen;
  my @top = grep { s|/.*||; !$seen{$_}++ } map { $_ } @{$self->{MANIFOUND}};
  if (@top > 1) {
    $self->{HAS_MULTIPLE_ROOT} = \@top;
    $ctx->abort_indexing_dist(DISTERROR('multiroot'));
  } else {
    $self->{DISTROOT} = $top[0];
  }
}

sub check_world_writable {
  my ($self, $ctx) = @_;
  my @files = @{$self->{MANIFOUND}};
  my @dirs = List::MoreUtils::uniq map {File::Basename::dirname($_) . "/"} @files;
  my $Ldirs = @dirs;
  while () {
    @dirs = List::MoreUtils::uniq map {($_,File::Basename::dirname($_) . "/")} @dirs;
    my $dirs = @dirs;
    last if $dirs == $Ldirs;
    $Ldirs = $dirs;
  }
  my @ww = grep {my @stat = stat $_; $stat[2] & 2} @dirs, @files;

  return unless @ww;

  $Logger->log([ "archive has world writable files: %s", [ sort @ww ] ]);
  $self->{HAS_WORLD_WRITABLE} = \@ww;
  $ctx->abort_indexing_dist(DISTERROR('worldwritable'));
}

sub filter_pms {
  my ($self, $ctx) = @_;
  my @pmfile;

  # very similar code is in PAUSE::package::filter_ppps
  MANI: for my $mf ( @{$self->{MANIFOUND}} ) {
    next unless $mf =~ /\.pm(?:\.PL)?$/i;
    my($inmf) = $mf =~ m!^[^/]+/(.+)!; # go one directory down

    # skip "t" - libraries in ./t are test libraries!
    # skip "xt" - libraries in ./xt are author test libraries!
    # skip "inc" - libraries in ./inc are usually install libraries
    # skip "local" - somebody shipped his carton setup!
    # skip 'perl5" - somebody shipped her local::lib!
    # skip 'fatlib' - somebody shipped their fatpack lib!
    # skip 'examples', 'example', 'ex', 'eg', 'demo' - example usage
    next if $inmf =~ m!^(?:x?t|inc|local|perl5|fatlib|examples?|ex|eg|demo)/!;

    if ($self->{META_CONTENT}){
      my $no_index = $self->{META_CONTENT}{no_index}
      || $self->{META_CONTENT}{private}; # backward compat
      if (ref($no_index) eq 'HASH') {
        my %map = (
          file => qr{\z},
          directory => qr{/},
        );
        for my $k (qw(file directory)) {
          next unless my $v = $no_index->{$k};
          my $rest = $map{$k};
          if (ref $v eq "ARRAY") {
            for my $ve (@$v) {
              $ve =~ s|/+$||;
              if ($inmf =~ /^$ve$rest/){
                $Logger->log("no_index rule on [$ve]; skipping file [$inmf]");
                next MANI;
              } else {
                $Logger->log_debug("no_index rule on [$ve]; NOT skipping file [$inmf]");
              }
            }
          } else {
            $v =~ s|/+$||;
            if ($inmf =~ /^$v$rest/){
              $Logger->log("no_index rule on [$v]; skipping file [$inmf]");
              next MANI;
            } else {
              $Logger->log_debug("no_index rule on [$v]; NOT skipping file [$inmf]");
            }
          }
        }
      } else {
        # noisy:
        # $Logger->log("no keyword 'no_index' or 'private' in META_CONTENT");
      }
    } else {
      # $Logger->log("no META_CONTENT"); # too noisy
    }
    push @pmfile, $mf;
  }

  $Logger->log([ "selected pmfiles to index: %s", \@pmfile ]);
  return \@pmfile;
}

sub _package_governing_permission {
  my $self = shift;

  my $d = CPAN::DistnameInfo->new($self->{DIST});
  my $dist_name = $d->dist;
  (my $main_pkg = $dist_name) =~ s/[-+]+/::/g;

  return $main_pkg;
}

sub _index_by_files {
  my ($self, $ctx, $pmfiles, $provides) = @_;
  my $dist = $self->{DIST};

  my $main_package = $self->_package_governing_permission;

  for my $pmfile (@$pmfiles) {
    if ($pmfile =~ m|/blib/|) {
      $ctx->alert("blib directory detected ($pmfile)");
      next;
    }

    $self->chown_unsafe;

    my $fio = PAUSE::pmfile->new(
      DIO => $self,
      PMFILE => $pmfile,
      USERID => $self->{USERID},
      META_CONTENT => $self->{META_CONTENT},
      MAIN_PACKAGE => $main_package,
    );
    $fio->examine_fio($ctx);
  }
}

sub _index_by_meta {
  my ($self, $ctx, $pmfiles, $provides) = @_;
  my $dist = $self->{DIST};

  my $main_package = $self->_package_governing_permission;

  my @packages;
  my @package_names =  map {[ $_ => $provides->{$_ }]} sort keys %$provides;
  PACKAGE: for (@package_names) {
    my ( $k, $v ) = @$_;

    unless (ref $v and length $v->{file}) {
      $Logger->log([ "badly formed provides metadata for package %s: %s", $k, $v ]);
      next PACKAGE;
    }

    $v->{infile} = "$v->{file}";
    my @stat = stat File::Spec->catfile($self->{DISTROOT}, $v->{file});
    if (@stat) {
      $v->{filemtime} = $stat[9];
    } else {
      $v->{filemtime} = 0;
    }
    unless (defined $v->{version}) {
      # 2009-09-23 get a bugreport due to
      # RKITOVER/MooseX-Types-0.20.tar.gz not
      # setting version for MooseX::Types::Util
      $v->{version} = "undef";
    }
    # going from a distro object to a package object
    # is only possible via a file object
    my $fio = PAUSE::pmfile->new
    (
      DIO => $self,
      PMFILE => $v->{infile},
      USERID => $self->{USERID},
      META_CONTENT => $self->{META_CONTENT},
    );
    my $pio = PAUSE::package->new(
      PACKAGE => $k,
      DIST => $dist,
      FIO => $fio,
      PP => $v,
      PMFILE => $v->{infile},
      USERID => $self->{USERID},
      META_CONTENT => $self->{META_CONTENT},
      MAIN_PACKAGE => $main_package,
    );

    push @packages, $pio;
  }

  $self->index_packages($ctx, \@packages);
}

sub index_packages {
    my ($self, $ctx, $packages) = @_;

    PACKAGE: for my $pkg (@$packages) {
        unless (eval { $pkg->examine_pkg($ctx); 1 }) {
            my $abort = $@;
            die $abort unless $abort->isa('PAUSE::Indexer::Abort::Package');

            next PACKAGE;
        }
    }
}

sub examine_pms {
  my ($self, $ctx) = @_;

  # XXX not yet reached, we need to re-examine what happens without SKIP.
  # Currently SKIP shadows the event of could_not_untar
  return if $self->{COULD_NOT_UNTAR};

  my $dist = $self->{DIST};

  my $pmfiles = $self->filter_pms($ctx);
  my ($meta, $provides, $indexing_method);

  if (my $version_from_meta_ok = $self->version_from_meta_ok($ctx)) {
    $meta = $self->{META_CONTENT};
    $provides = $meta->{provides};
    if ($provides && "HASH" eq ref $provides) {
      $indexing_method = '_index_by_meta';
    }
  }

  if (! $indexing_method && @$pmfiles) { # examine files
    $indexing_method = '_index_by_files';
  }

  if ($indexing_method) {
    $self->$indexing_method($ctx, $pmfiles, $provides);
  } else {
    $ctx->alert("Couldn't determine an indexing method!");
  }
}

sub chown_unsafe {
  my($self) = @_;
  return if $self->{CHOWN_UNSAFE_DONE};
  use File::Find;
  my(undef,undef,$uid,$gid) = getpwnam($PAUSE::Config->{ML_CHOWN_USER});
  die "user $PAUSE::Config->{ML_CHOWN_USER} not found, cannot continue" unless defined $uid;
  find(sub {
      chown $uid, $gid, $_;
    },
    "."
  );
  $self->{CHOWN_UNSAFE_DONE}++;
}

sub read_dist {
  my ($self, $ctx) = @_;

  my @manifind;
  my $ok = eval { @manifind = sort keys %{ExtUtils::Manifest::manifind()}; 1 };
  $self->{MANIFOUND} = \@manifind;
  unless ($ok) {
    my $error = $@;
    $Logger->log([ "errors in manifind: %s", $error ]);
    return;
  }

  my $manifound = @manifind;
  my $dist = $self->{DIST};
  unless (@manifind) {
    $Logger->log("!? no files in dist");
    return;
  }

  $Logger->log([
    "found %u files in dist, first is [%s]",
    $manifound,
    $manifind[0]
  ]);
}

sub extract_readme_and_meta {
  my ($self, $ctx) = @_;
  my($suffix) = $self->{SUFFIX};
  return unless $suffix;
  my $dist = $self->{DIST};
  my $MLROOT = $self->mlroot;
  my @manifind = @{$self->{MANIFOUND}};
  my(@readme) = grep /(^|\/)readme/i, @manifind;
  my($sans) = $dist =~ /(.*)\.\Q$suffix\E$/;
  if (@readme) {
    my $readme;
    if ($sans =~ /-bin-?(.*)/) {
      my $vers_arch = quotemeta $1;
      my @grep;
      while ($vers_arch) {
        if (@grep = grep /$vers_arch/, @readme) {
          @readme = @grep;
          last;
        }
        $vers_arch =~ s/^[^\-]+-?//;
      }
    }
    $readme = $readme[0];
    for (1..$#readme) {
      $readme = $readme[$_] if length($readme[$_]) < length($readme);
    }
    $self->{README} = $readme;
    File::Copy::copy $readme, "$MLROOT/$sans.readme";
    utime((stat $readme)[8,9], "$MLROOT/$sans.readme");
    PAUSE::newfile_hook("$MLROOT/$sans.readme");
  } else {
    $self->{README} = "No README found";
    $Logger->log("no README found");
  }
  my ($json, $yaml);
  if ($self->perl_major_version == 6) {
    $json = List::Util::reduce { length $a < length $b ? $a : $b }
            grep !m|/t/|, grep m|META6\.json$|, @manifind;
  }
  else {
    $json = List::Util::reduce { length $a < length $b ? $a : $b }
            grep !m|/t/|, grep m|/META\.json$|, @manifind;
    $yaml = List::Util::reduce { length $a < length $b ? $a : $b }
            grep !m|/t/|, grep m|/META\.yml$|, @manifind;
  }

  unless ($json || $yaml) {
    $self->{METAFILE} = "No META.yml or META.json found";
    $ctx->abort_indexing_dist(DISTERROR('no_meta'));
    return;
  }

  # META.json located only in a subdirectory should not precede
  # META.yml located in the top directory. (eg. Test::Module::Used 0.2.4)
  if ($json && $yaml && length($json) > length($yaml) + 1) {
    $json = '';
  }

  for my $metafile ($json || $yaml) {
    if (-s $metafile) {
      $self->{METAFILE} = $metafile;
      if ($self->perl_major_version == 6) {
        $self->write_updated_meta6_json($metafile, $MLROOT, $dist, $sans);
      } else {
        File::Copy::copy $metafile, "$MLROOT/$sans.meta";
      }
      utime((stat $metafile)[8,9], "$MLROOT/$sans.meta");
      PAUSE::newfile_hook("$MLROOT/$sans.meta");
      my $ok = eval {
        $self->{META_CONTENT} = Parse::CPAN::Meta->load_file($metafile); 1
      };
      unless ($ok) {
        my $error = $@;
        $Logger->log([ "error while parsing $metafile: %s", $error ]);
        $self->{META_CONTENT} = {};
        $self->{METAFILE} = "$metafile found but error "
                          . "encountered while loading: $@";
      }
    } else {
      $self->{METAFILE} = "Empty $metafile found, ignoring\n";
    }
  }
}

sub check_indexability {
    my ($self, $ctx) = @_;
    if ($self->{META_CONTENT}{distribution_type}
        && $self->{META_CONTENT}{distribution_type} =~ m/^(script)$/) {
        return;
    }

    $Logger->log([
      "release status: %s",
      $self->{META_CONTENT}{release_status},
    ]);

    if (($self->{META_CONTENT}{release_status} // 'stable') ne 'stable') {
        # META.json / META.yml declares it's not stable; do not index!
        $ctx->abort_indexing_dist(DISTERROR('unstable_release'));
        return;
    }
}

sub write_updated_meta6_json {
  my($self, $metafile, $MLROOT, $dist, $sans) = @_;

  my $json = JSON::XS->new->utf8->canonical->pretty;

  open my $meta_fh, '<', $metafile
    or $Logger->log("failed to open META6.json file for reading: $!");
  my $meta = eval {
    $json->decode(join '', <$meta_fh>);
  };
  if ($@) {
    $Logger->log("failed to parse META6.json file: $@");
    File::Copy::copy $metafile, "$MLROOT/$sans.meta";
    return;
  }
  close $meta_fh;

  $meta->{'source-url'} = $PAUSE::Config->{PUB_MODULE_URL} . $dist;

  open $meta_fh, '>', "$MLROOT/$sans.meta"
    or $Logger->log("failed to open Perl 6 meta file for writing: $!");
  print { $meta_fh } $json->encode($meta)
    or $Logger->log("failed to write Perl 6 meta file: $!");
  close $meta_fh;
}

sub version_from_meta_ok {
  my ($self, $ctx) = @_;
  return $self->{VERSION_FROM_META_OK} if exists $self->{VERSION_FROM_META_OK};
  my $c = $self->{META_CONTENT};

  # If there's no provides hash, we can't get our module versions from the
  # provides hash! -- rjbs, 2012-03-31
  return($self->{VERSION_FROM_META_OK} = 0) unless $c->{provides};

  # Some versions of Module::Build generated an empty provides hash.  If we're
  # *not* looking at a Module::Build-generated metafile, then it's okay.
  my ($mb_v) = ($c->{generated_by} // '') =~ /Module::Build version ([\d\.]+)/;
  return($self->{VERSION_FROM_META_OK} = 1) unless $mb_v;

  # ??? I don't know why this is here.
  return($self->{VERSION_FROM_META_OK} = 1) if $mb_v eq '0.250.0';

  if ($mb_v >= 0.19 && $mb_v < 0.26 && ! keys %{$c->{provides}}) {
      # RSAVAGE/Javascript-SHA1-1.01.tgz had an empty provides hash. Ron
      # did not find the reason why this happened, but let's not go
      # overboard, 0.26 seems a good threshold from the statistics: there
      # are not many empty provides hashes from 0.26 up.
      return($self->{VERSION_FROM_META_OK} = 0);
  }

  # We're not in the suspect range of M::B versions.  It's good to go.
  return($self->{VERSION_FROM_META_OK} = 1);
}

sub lock {
  my($self) = @_;
  if ($self->hub->{'SKIP-LOCKING'}) {
    $Logger->log("forcing indexing without a lock");
    return 1;
  }
  my $dist = $self->{DIST};
  my $dbh = $self->connect;
  my $rows_affected = $dbh->do(
    "UPDATE distmtimes SET indexing_at=?
    WHERE dist=?
      AND indexing_at IS NULL",
    undef,
    PAUSE->_now_string,
    $dist,
  );
  return 1 if $rows_affected > 0;

  my $row = $dbh->selectrow_hashref(
    "SELECT * FROM distmtimes WHERE dist=?",
    undef,
    $dist,
  );

  if ($row) {
    $Logger->log([
      "can't get lock, current record is: %s",
      $row,
    ]);
  } else {
    $Logger->log("weird: first we get no lock, then the record is gone???");
  }
  return;
}

sub set_indexed {
  my ($self, $ctx) = @_;
  my $dist = $self->{DIST};
  my $dbh = $self->connect;
  my $rows_affected = $dbh->do(
    "UPDATE distmtimes SET indexed_at=?  WHERE dist=?",
    undef,
    PAUSE->_now_string,
    $dist,
  );
  $rows_affected > 0;
}

sub p6_dist_meta_ok {
  my $self = shift;
  my $c    = $self->{META_CONTENT};
  $c &&
  $c->{name} &&
  $c->{version} &&
  $c->{description}
}

sub p6_index_dist {
  my ($self, $ctx) = @_;
  my $dbh    = $self->connect;
  my $dist   = $self->{DIST};
  my $MLROOT = $self->mlroot;
  my $userid = $self->{USERID} or die;
  my $c      = $self->{META_CONTENT};

  local($dbh->{RaiseError}) = 0;
  local($dbh->{PrintError}) = 0;

  my $p6dists    = "INSERT INTO p6dists (name, auth, ver, tarball, indexed_at) VALUES (?,?,?,?,?)";
  my $p6provides = "INSERT INTO p6provides (name, tarball) VALUES (?,?)";
  my $p6binaries = "INSERT INTO p6binaries (name, tarball) VALUES (?,?)";

  ###
  # Index distribution itself.
  my @args = ($c->{name}, $userid, $c->{version}, $dist, PAUSE->_now_string);
  my $ret  = $dbh->do($p6dists, undef, @args);
  pop @args; # we do not use the "now string" in the sprintf below
  push @args, (defined $ret ? '' : $dbh->errstr), ($ret || '');
  $Logger->log([
    "inserted into p6dists: %s", {
      name    => $args[0],
      auth    => $args[1],
      ver     => $args[2],
      tarball => $args[3],
      ret     => $args[4],
      err     => $args[5],
    },
  ]);

  return "ERROR in dist $dist: " . $dbh->errstr unless $ret;

  ###
  # Index provides section. This section is allowed to be empty or absent, in case this
  # distribution is about binaries or shared files.
  for my $namespace (keys %{$c->{provides} // {}}) {
    @args = ($namespace, $dist);
    $ret  = $dbh->do($p6provides, undef, @args);
    push @args, (defined $ret ? '' : $dbh->errstr), ($ret || '');
    $Logger->log([
      "inserted into p6provides: %s", {
        name    => $args[0],
        tarball => $args[1],
        ret     => $args[2],
        err     => $args[3],
      },
    ]);
  }
  return "ERROR in dist $dist: " . $dbh->errstr unless $ret;

  ###
  # Index binaries. We need to scan the archives content for this.
  local *TARTEST;
  my $tarbin = $self->hub->{TARBIN};
  my $tar_opt = "tzf";
  if ($dist =~ /\.(?:tar\.bz2|tbz)$/) {
    $tar_opt = "tjf";
  }
  open TARTEST, "$tarbin $tar_opt $MLROOT/$dist |";
  while (<TARTEST>) {
    if (m:^bin/([^/]+)$:) {
      @args = ($1, $dist);
      $ret  = $dbh->do($p6binaries, undef, @args);
      push @args, (defined $ret ? '' : $dbh->errstr), ($ret || '');
      $Logger->log([
        "inserted into p6binaries: %s", {
          name    => $args[0],
          tarball => $args[1],
          ret     => $args[2],
          err     => $args[3],
        },
      ]);
    }
  }
  unless (close TARTEST) {
    $Logger->log("could not untar!");
    $ctx->alert("Could not untar!");
    $self->{COULD_NOT_UNTAR}++;
    return "ERROR: Could not untar $dist!";
  }
  return "ERROR in dist $dist: " . $dbh->errstr unless $ret;

  return 0; # Success!
}

1;
__END__

=head1 NAME

PAUSE::dist - Class representing one distribution

=head1 SYNOPSIS

  my $dio = PAUSE::dist->new(
    HUB    => $mldistwatch,
    DIST   => $dist,
  );

=head1 DESCRIPTION

Encapsulates operations on a distro, either in the database, in a
(possibly compressed archive), or unpacked on disk.

=head2 Methods

=head3 new

Constructor.

=head3 examine_dist

Does these checks:

  PAUSE::isa_regular_perl($dio->dist)
  $dio->isa_dev_version
  $dist =~ m|/perl-\d+|

Then unpacks the distro into a local directory.

=head3 read_dist

Reads the distro's F<MANIFEST>.

=head3 extract_readme_and_meta

Copies the shortest-named README file, and metadata files, out to
top-level as F<$distroname.readme> et al.

=head3 filter_pms

Goes through all F<*.pm> files, removing test and install libs, and
applying the metadata's C<no_index> rules. Returns ref to array with
filenames.

=head3 version_from_meta_ok

Can the version be got from the metadata?

=head3 check_blib

=head3 check_multiple_root

=head3 check_world_writable

Check various aspects of the distro.

=head3 examine_pms

Calls L<filter_pms>, L<version_from_meta_ok>, and then an index method.

=head3 ignoredist

Whether is really a distro vs a F<*.readme>.

=head3 mtime_ok

Whether the distro has changed since "last time".

=head3 delete_goner

Delete database entry for this distro.

=head3 writechecksum

=head3 alert

=head3 untar

=head3 perl_major_version

Is this a distro for Perl 5 or 6?

=head3 skip

Accessor method. True if perl distro from non-pumpking or a dev release.

=head3 _examine_regular_perl

=head3 isa_dev_version

=head3 connect

=head3 disconnect

=head3 mlroot

=head3 mail_summary

=head3 _package_governing_permission

The package used to determine whether the uploader may upload this distro.

=head3 _index_by_files

=head3 _index_by_meta

=head3 chown_unsafe

=head3 verbose

=head3 lock

=head3 set_indexed

Insert this distro into the database.

=head3 p6_dist_meta_ok

Is the metadata for this Perl 6 distro good?

=head3 p6_index_dist

Index this Perl 6 distro.
