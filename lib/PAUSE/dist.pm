use strict;
use warnings;
package PAUSE::dist;
use vars qw(%CHECKSUMDONE $AUTOLOAD $YAML_MODULE);

use Email::Sender::Simple qw(sendmail);
use File::Copy ();
use List::MoreUtils ();
use Parse::CPAN::Meta;
use PAUSE::mldistwatch::Constants;

# ISA_REGULAR_PERL means a perl release for public consumption
# (and must exclude developer releases like 5.9.4). I need to
# rename it from ISAPERL to ISA_REGULAR_PERL to avoid
# confusion with CPAN.pm. CPAN.pm has a different regex for
# ISAPERL because there we want to protect the user from
# developer releases too, but here we want to index a distro
# with very special treatment that is only reserved for "real"
# perl distros. (The exclusion of developer releases was
# accidentally lost in rev 815)
our $ISA_REGULAR_PERL = qr{
    /
    ( perl-5[._-](\d{3}(_[0-4][0-9])?|\d*[02468]\.\d+)
    | perl5[._](00\d(_[0-4][0-9])?)
    | ponie-[\d.\-]
    )
    (?: \.tar[._-]gz
    |   \.tar\.bz2
    )
    \z
}x;

# package PAUSE::dist
sub DESTROY {}

# package PAUSE::dist;
sub new {
  my($me) = shift;
  bless { @_ }, ref($me) || $me;
}

# package PAUSE::dist;
sub ignoredist {
  my $self = shift;
  my $dist = $self->{DIST};
  if ($dist =~ m|/\.|) {
    $self->verbose(1,"Warning: dist[$dist] has illegal filename\n");
    return 1;
  }
  return 1 if $dist =~ /(\.readme|\.sig|\.meta|CHECKSUMS)$/;
  # Stupid to have code that needs to be maintained in two places,
  # here and in edit.pm:
  return 1 if $dist =~ m!CNANDOR/(?:mp_(?:app|debug|doc|lib|source|tool)|VISEICat(?:\.idx)?|VISEData)!;
  if ($self->{PICK}) {
    return 1 unless $self->{PICK}{$dist};
  }
  return;
}

# package PAUSE::dist;
sub delete_goner {
  my $self = shift;
  my $dist = $self->{DIST};
  if ($self->{PICK} && $self->{PICK}{$dist}) {
    $self->verbose(1,"Warning: parameter pick '$dist' refers to a goner, ignoring");
    return;
  }
  my $dbh = $self->connect;
  $dbh->do("DELETE FROM packages WHERE dist='$dist'");
  $dbh->do("DELETE FROM distmtimes WHERE dist='$dist'");
}

# package PAUSE::dist;
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
  eval { CPAN::Checksums::updatedir($dir); };
  if ($@) {
    $self->verbose(1,"CPAN::Checksums::updatedir died with error[$@]");
    return; # a die might cause even more trouble
  }
  return unless -e "$dir/CHECKSUMS"; # e.g. only files-to-ignore
  PAUSE::newfile_hook("$dir/CHECKSUMS");
}

# package PAUSE::dist;
sub mtime_ok {
  my $self = shift;
  my $otherts = shift || 0;
  my $dist = $self->{DIST};
  my $dbh = $self->connect;
  unless ($otherts){ # positive $otherts means it was alive last time
    # Hahaha: he didn't think of the programmer who wants to
    # introduce locking:
    # $dbh->do("DELETE FROM distmtimes WHERE dist='$dist'");

    local($dbh->{RaiseError}) = 0;
    # this may fail if we have a race condition, but we'll
    # decide later if this is the case:
    $dbh->do("INSERT INTO distmtimes (dist) VALUES ('$dist')");
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
        qq{UPDATE distmtimes SET distmtime=?, distmdatetime=?
        WHERE dist=?},
        undef,
        $mtime,
        PAUSE->_time_string($mtime),
        $dist,
      );
      $self->verbose(1,"Assigned mtime '$mtime' to dist '$dist'\n");
      return 1;
    }
  }
  if ($self->{PICK}{$dist}) {
    return 1;
  }
  return;
}

# package PAUSE::dist;
sub alert {
  my $self = shift;
  my $what = shift;
  if (defined $what) {
    $self->{ALERT} ||= "";
    $self->{ALERT} .= " $what";
  } else {
    return $self->{ALERT};
  }
}

# package PAUSE::dist;
sub untar {
  my $self = shift;
  my $dist = $self->{DIST};
  local *TARTEST;
  my $tarbin = $self->{TARBIN};
  my $MLROOT = $self->mlroot;
  my $tar_opt = "tzf";
  if ($dist =~ /\.(?:tar\.bz2|tbz)$/) {
    $tar_opt = "tjf";
  }
  open TARTEST, "$tarbin $tar_opt $MLROOT/$dist |";
  while (<TARTEST>) {
    if (m:^\.\./: || m:/\.\./: ) {
      $self->verbose(1,"*** ALERT: Updir detected in $dist!\n\n");
      $self->alert("ALERT: Updir detected in $dist!");
      $self->{COULD_NOT_UNTAR}++;
      return;
    }
  }
  unless (close TARTEST) {
    $self->verbose(1,"Could not untar $dist!\n");
    $self->alert("\nCould not untar $dist!\n");
    $self->{COULD_NOT_UNTAR}++;
    return;
  }
  $tar_opt = "xzf";
  if ($dist =~ /\.(?:tar\.bz2|tbz)$/) {
    $tar_opt = "xjf";
  }
  $self->verbose(1,"Going to untar. Running '$tarbin' '$tar_opt' '$MLROOT/$dist'\n");
  unless (system($tarbin,$tar_opt,"$MLROOT/$dist")==0) {
    $self->verbose(1, "Some error occurred during unzipping. Let's retry with -v:\n");
    unless (system("$tarbin v$tar_opt $MLROOT/$dist")==0) {
      $self->verbose(1, "Some error occurred during unzipping again; giving up\n");
    }
  }
  $self->verbose(1,"Untarred '$MLROOT/$dist'\n");
  return 1;
}

# package PAUSE::dist;
sub skip { shift->{SKIP} }

sub isa_regular_perl {
  my($self,$dist) = @_;
  scalar $dist =~ /$PAUSE::dist::ISA_REGULAR_PERL/;
}

# package PAUSE::dist;
sub examine_dist {
  my($self) = @_;
  my $dist = $self->{DIST};
  my $MLROOT = $self->mlroot;
  my($suffix,$skip);
  $suffix = $skip = "";
  # should use CPAN::DistnameInfo but note: "zip" not contained
  # because it is special-cased below
  my $suffqr = qr/\.(tgz|tbz|tar[\._-]gz|tar\.bz2|tar\.Z)$/;
  if ($self->isa_regular_perl($dist)) {
    my($u) = PAUSE::dir2user($dist); # =~ /([A-Z][^\/]+)/; # XXX dist2user
    use DBI;
    my $adbh = DBI->connect(
      $PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME},
      $PAUSE::Config->{AUTHEN_DATA_SOURCE_USER},
      $PAUSE::Config->{AUTHEN_DATA_SOURCE_PW},
    ) or die $DBI::errstr;
    my $query = "SELECT * FROM grouptable
    WHERE user= ?
      AND ugroup='pumpking'";
    my $sth = $adbh->prepare($query);
    $sth->execute($u);
    if ($sth->rows > 0){
      $skip = 0;
      $self->verbose(1,"Perl dist $dist from trusted user $u");
    } else {
      $skip = 1;
      $self->verbose(1,"*** ALERT: Perl dist $dist from untrusted user $u. Skip set to [$skip]\n");
    }
    $sth->finish;
    $adbh->disconnect;
    if ($dist =~ $suffqr) {
      $suffix = $1;
    } else {
      $self->verbose(1,"A perl distro ($dist) with an unusual suffix!\n");
      $self->alert("A perl distro ($dist) with an unusual suffix!");
    }
    unless ($skip) {
      $skip = 1 unless $self->untar;
    }
  } else {                # ! isa_regular_perl
    if (
      $dist =~ /\d\.\d+_\d/
      ||
      $dist =~ /TRIAL/
      ||
      $dist =~ m|/perl-\d+\.\d+\.\d+-RC\d+\.|x
    ) {
      $self->verbose(1,"Dist '$dist' is a developer release\n");
      $self->{SUFFIX} = "N/A";
      $self->{SKIP}   = 1;
      return;
    }
    if ($dist =~ $suffqr) {
      $suffix = $1;
      $skip = 1 unless $self->untar;
    } elsif ($dist =~ /\.pm\.(Z|gz)$/) {
      # By not setting suffix we prohibit extracting README
      my $file = File::Basename::basename($dist);
      File::Copy::copy "$MLROOT/$dist", $file;
      my $willunzip = $file;
      $willunzip =~ s/\.(Z|gz)$//;
      unless (PAUSE::gunzip($file,$willunzip)) {
        $self->verbose(1,"Failed gunzip on $file\n");
      }
    } elsif ($dist =~ /\.zip$/) {
      $suffix = "zip";
      my $unzipbin = $self->{UNZIPBIN};
      my $system = "$unzipbin $MLROOT/$dist > /dev/null 2>&1";
      unless (system($system)==0) {
        $self->verbose(1,
          "Some error occurred during unzippping. ".
          "Let's read unzip -t:\n");
        system("$unzipbin -t $MLROOT/$dist");
      }
    } else {
      $self->verbose(1,"File '$dist' does not resemble a distribution");
      $skip = 1;
    }
  }
  $self->{SUFFIX} = $suffix;
  $self->{SKIP}   = $skip;
}

# package PAUSE::dist
sub connect {
  my($self) = @_;
  my $main = $self->{MAIN};
  $main->connect;
}

# package PAUSE::dist
sub disconnect {
  my($self) = @_;
  my $main = $self->{MAIN};
  $main->disconnect;
}

# package PAUSE::dist
sub mlroot {
  my($self) = @_;
  my $main = $self->{MAIN};
  $main->mlroot;
}

# package PAUSE::dist;
sub mail_summary {
  my($self) = @_;
  my $distro = $self->{DIST};
  my $author = PAUSE::dir2user($distro);
  my @m;

  push @m, "The following report has been written by the PAUSE namespace indexer.
  Please contact modules\@perl.org if there are any open questions.\n";
  my $time = gmtime;
  my $MLROOT = $self->mlroot;
  my $mtime = gmtime((stat "$MLROOT/$distro")[9]);
  my $nfiles = scalar @{$self->{MANIFOUND}};
  my $pmfiles = grep /\.pm$/, @{$self->{MANIFOUND}};
  my $dbh = $self->connect;
  my $sth = $dbh->prepare("SELECT asciiname, fullname
    FROM   users
    WHERE userid=?");
  $sth->execute($author);
  my($u) = $sth->fetchrow_hashref;
  my $asciiname = $u->{asciiname} || $u->{fullname} || "name unknown";
  my $substrdistro = substr $distro, 5;
  my($distrobasename) = $substrdistro =~ m|.*/(.*)|;
  my $versions_from_meta = $self->version_from_meta_ok ? "yes" : "no";
  my $parse_cpan_meta_version = Parse::CPAN::Meta->VERSION;
  push @m, qq[
  User: $author ($asciiname)
  Distribution file: $distrobasename
  Number of files: $nfiles
  *.pm files: $pmfiles
  README: $self->{README}
  META-File: $self->{METAFILE}
  META-Parser: Parse::CPAN::Meta $parse_cpan_meta_version
  META-driven index: $versions_from_meta
  Timestamp of file: $mtime UTC
  Time of this run: $time UTC\n\n];
  my $tf = Text::Format->new(firstIndent=>0);

  my $status_over_all;

  if (0) {
  } elsif ($self->{HAS_MULTIPLE_ROOT}) {

    push @m, $tf->format(qq[The distribution does not unpack
      into a single directory and is therefore not being
      indexed. Hint: try 'make dist' or 'Build dist'. (The
        directory entries found were: @{$self->{HAS_MULTIPLE_ROOT}})]);

    push @m, qq{\n\n};

    $status_over_all = "Failed";

  } elsif ($self->{HAS_WORLD_WRITABLE}) {

    push @m, $tf->format(qq[The distribution contains the
      following world writable directories or files and is
      therefore considered a security breach and as such not
      being indexed: @{$self->{HAS_WORLD_WRITABLE}} . See
      also http://use.perl.org/~bart/journal/38127]);

    push @m, qq{\n\n};

    if ($self->{HAS_WORLD_WRITABLE_FIXEDFILE}) {

      push @m, $tf->format(qq[For your convenience PAUSE has
        tried to write a new tarball with all the
        world-writable bits removed. The file is put on
        the CPAN as
        '$self->{HAS_WORLD_WRITABLE_FIXEDFILE}' along with
        your upload and will be indexed automatically
        unless there are other errors that prevent that.
        Please watch for a separate indexing report.]);

      push @m, qq{\n\n};

    } else {

      my $err = join "\n", @{$self->{HAS_WORLD_WRITABLE_FIXINGERRORS}||[]};
      $self->alert("Fixing a world-writable tarball failed: $err");

    }

    $status_over_all = "Failed";

  } elsif ($self->{HAS_BLIB}) {

    push @m, $tf->format(qq{The distribution contains a blib/
      directory and is therefore not being indexed. Hint:
      try 'make dist'.});

    push @m, qq{\n\n};

    $status_over_all = "Failed";

  } else {
    my $inxst = $self->{INDEX_STATUS};
    if ($inxst && ref $inxst && %$inxst) {
      my $Lstatus = 0;
      my $intro_written;
      for my $p (sort {
          $inxst->{$b}{status} <=> $inxst->{$a}{status}
            or
          $a cmp $b
        } keys %$inxst) {
        my $status = $inxst->{$p}{status};
        unless (defined $status_over_all) {
          if ($status) {
            if ($status > PAUSE::mldistwatch::Constants::OK) {
              $status_over_all =
              PAUSE::mldistwatch::Constants::heading($status)
              || "UNKNOWN (status=$status)";
            } else {
              $status_over_all = "OK";
            }
          } else {
            $status_over_all = "Unknown";
          }
          push @m, "Status of this distro: $status_over_all\n";
          push @m, "="x(length($status_over_all)+23), "\n\n";
        }
        unless ($intro_written++) {
          push @m, qq{The following packages (grouped by }.
          qq{status) have been found in the distro:\n\n};
        }
        if ($status != $Lstatus) {
          my $heading =
          PAUSE::mldistwatch::Constants::heading($status) ||
          "UNKNOWN (status=$status)";
          push @m, sprintf "Status: %s
          %s\n\n", $heading, "="x(length($heading)+8);
        }
        my $tf13 = Text::Format->new(
          bodyIndent => 13,
          firstIndent => 13,
        );
        my $verb_status = $tf13->format($inxst->{$p}{verb_status});
        $verb_status =~ s/^\s+//; # otherwise this line is too long
        # magic words, see also report02() around line 573, same wording there,
        # exception prompted by JOESUF/libapreq2-2.12.tar.gz
        $inxst->{$p}{infile} ||= "missing in META.yml, tolerated by PAUSE indexer";
        push @m, sprintf("     module: %s
          version: %s
          in file: %s
          status: %s\n",
          $p,
          $inxst->{$p}{version},
          $inxst->{$p}{infile},
          $verb_status,
        );
        $Lstatus = $status;
      }
    } else {
      warn sprintf "st[%s]", Data::Dumper::Dumper($inxst);
      if ($pmfiles > 0) {
        if ($self->version_from_meta_ok) {

          push @m, qq{Nothing in this distro has been
          indexed, because according to META.yml this
          package does not provide any modules.\n\n};
          $status_over_all = "Empty_provides";

        } else {

          push @m, qq{No or no indexable package
          statements could be found in the distro (maybe a
          script or documentation distribution or a
          developer release?)\n\n};
          $status_over_all = "Empty_no_pm";

        }
      } else {
        # no need to write a report at all
        return;
      }

    }
  }
  push @m, qq{__END__\n};
  my $pma = PAUSE::MailAddress->new_from_userid($author);
  if ($PAUSE::Config->{TESTHOST} || $self->{MAIN}{OPT}{testhost}) {
    if ($self->{PICK}) {
      local $"="";
      warn "Unsent Report [@m]";
    }
  } else {
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
        body_str => join( ($, // q{}) , @m),
    );

    sendmail($email);

    $self->verbose(1,"Sent \"indexer report\" mail about $substrdistro\n");
  }
}

# package PAUSE::dist;
sub index_status {
  my($self,$pack,$version,$infile,$status,$verb_status) = @_;
  $self->{INDEX_STATUS}{$pack} = {
    version => $version,
    infile => $infile,
    status => $status,
    verb_status => $verb_status,
  };
}

# package PAUSE::dist;
sub check_blib {
  my($self) = @_;
  if (grep m|^[^/]+/blib/|, @{$self->{MANIFOUND}}) {
    $self->{HAS_BLIB}++;
    return;
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
        $self->alert("ENDLESS LOOP detected in $self->{DIST}!");
        last DIRDOWN;
      }
      next DIRDOWN;
    }
    # more than one entry in this directory means final check
    if (grep m|^blib/|, @found) {
      $self->{HAS_BLIB}++;
    }
    last DIRDOWN;
  }
}

# package PAUSE::dist;
sub check_multiple_root {
  my($self) = @_;
  my %seen;
  my @top = grep { s|/.*||; !$seen{$_}++ } map { $_ } @{$self->{MANIFOUND}};
  if (@top > 1) {
    $self->verbose(1,"HAS_MULTIPLE_ROOT: top[@top]");
    $self->{HAS_MULTIPLE_ROOT} = \@top;
  } else {
    $self->{DISTROOT} = $top[0];
  }
}

# package PAUSE::dist;
sub check_world_writable {
  my($self) = @_;
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
  if (@ww) {
    # XXX todo: set a variable if we could successfully build the
    # new tarball and make it visible for debugging and later
    # visible for the user

    # we are now in temp dir and in front of us is
    # $self->{DISTROOT}, e.g. 'Tk-Wizard-2.142' (the directory, not necessarily the significant part of the distro name)
    my @wwfixingerrors;
    for my $wwf (@ww) {
      my @stat = stat $wwf;
      unless (chmod $stat[2] &~ 0022, $wwf) {
        push @wwfixingerrors, "error during 'chmod $stat[2] &~ 0022, $wwf': $!";
      }
    }
    my $fixedfile = "$self->{DISTROOT}-withoutworldwriteables.tar.gz";
    my $todir = File::Basename::dirname($self->{DIST}); # M/MA/MAKAROW
    my $to_abs = "$self->{MAIN}{MLROOT}/$todir/$fixedfile";
    if (! length $self->{DISTROOT}) {
      push @wwfixingerrors, "Alert: \$self->{DISTROOT} is empty, cannot fix";
    } elsif ($self->{DIST} =~ /-withoutworldwriteables/) {
      push @wwfixingerrors, "Sanity check failed: incoming file '$self->{DIST}' already has '-withoutworldwriteables' in the name";
    } elsif (-e $to_abs) {
      push @wwfixingerrors, "File '$to_abs' already exists, won't overwrite";
    } elsif (0 != system (tar => "czf",
        $to_abs,
        $self->{DISTROOT}
      )) {
      push @wwfixingerrors, "error during 'tar ...': $!";
    }
    $self->verbose(1,"HAS_WORLD_WRITABLE: ww[@ww]");
    $self->{HAS_WORLD_WRITABLE} = \@ww;
    if (@wwfixingerrors) {
      $self->{HAS_WORLD_WRITABLE_FIXINGERRORS} = \@wwfixingerrors;
    } else {
      $self->{HAS_WORLD_WRITABLE_FIXEDFILE} = $fixedfile;
    }
  }
}

# package PAUSE::dist;
sub filter_pms {
  my($self) = @_;
  my @pmfile;

  # very similar code is in PAUSE::package::filter_ppps
  MANI: for my $mf ( @{$self->{MANIFOUND}} ) {
    next unless $mf =~ /\.pm(?:\.PL)?$/i;
    my($inmf) = $mf =~ m!^[^/]+/(.+)!; # go one directory down
    next if $inmf =~ m!^(?:t|inc)/!;
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
                $self->verbose(1,"Skipping inmf[$inmf] due to ve[$ve]");
                next MANI;
              } else {
                $self->verbose(1,"NOT skipping inmf[$inmf] due to ve[$ve]");
              }
            }
          } else {
            $v =~ s|/+$||;
            if ($inmf =~ /^$v$rest/){
              $self->verbose(1,"Skipping inmf[$inmf] due to v[$v]");
              next MANI;
            } else {
              $self->verbose(1,"NOT skipping inmf[$inmf] due to v[$v]");
            }
          }
        }
      } else {
        # noisy:
        # $self->verbose(1,"no keyword 'no_index' or 'private' in META_CONTENT");
      }
    } else {
      # $self->verbose(1,"no META_CONTENT"); # too noisy
    }
    push @pmfile, $mf;
  }
  $self->verbose(1,"Finished with pmfile[@pmfile]\n");
  \@pmfile;
}

# package PAUSE::dist;
sub examine_pms {
  my $self = shift;
  return if $self->{HAS_BLIB};
  return if $self->{HAS_MULTIPLE_ROOT};
  return if $self->{HAS_WORLD_WRITABLE};
  return if $self->{COULD_NOT_UNTAR}; # XXX not yet reached, we
  # need to re-examine what
  # happens without SKIP.
  # Currently SKIP shadows
  # the event of
  # could_not_untar
  my $dist = $self->{DIST};

  my $binary_dist;
  # ftp://ftp.funet.fi/pub/CPAN/modules/05bindist.convention.html
  $binary_dist = 1 if $dist =~ /\d-bin-\d+-/i;

  my $pmfiles = $self->filter_pms;
  my($yaml,$provides,$indexingrule);
  if (my $version_from_meta_ok = $self->version_from_meta_ok) {
    $yaml = $self->{META_CONTENT};
    $provides = $yaml->{provides};
    if (!$indexingrule && $provides && "HASH" eq ref $provides) {
      $indexingrule = 2;
    }
  }
  if (!$indexingrule && @$pmfiles) { # examine files
    $indexingrule = 1;
  }
  if (0) {
  } elsif (1==$indexingrule) { # examine files
    for my $pmfile (@$pmfiles) {
      if ($binary_dist) {
        next unless $pmfile =~ /\b(Binary|Port)\b/; # XXX filename good,
        # package would be
        # better
      } elsif ($pmfile =~ m|/blib/|) {
        $self->alert("Still a blib directory detected:
          dist[$dist]pmfile[$pmfile]
          ");
        next;
      }

      $self->chown_unsafe;

      my $fio = PAUSE::pmfile->new(
        DIO => $self,
        PMFILE => $pmfile,
        TIME => $self->{TIME},
        USERID => $self->{USERID},
        META_CONTENT => $self->{META_CONTENT},
      );
      $fio->examine_fio;
    }
  } elsif (2==$indexingrule) { # a yaml with provides
    while (my($k,$v) = each %$provides) {
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
        TIME => $self->{TIME},
        USERID => $self->{USERID},
        META_CONTENT => $self->{META_CONTENT},
      );
      my $pio = PAUSE::package
      ->new(
        PACKAGE => $k,
        DIST => $dist,
        FIO => $fio,
        PP => $v,
        TIME => $self->{TIME},
        PMFILE => $v->{infile},
        USERID => $self->{USERID},
        META_CONTENT => $self->{META_CONTENT},
      );
      $pio->examine_pkg;
    }
  } else {
    $self->alert("Does this work out elsewhere? Neither yaml nor pmfiles indexing in dist[$dist]???");
  }
}

# package PAUSE::dist
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

# package PAUSE::dist;
sub read_dist {
  my $self = shift;
  my(@manifind) = sort keys %{ExtUtils::Manifest::manifind()};
  my $manifound = @manifind;
  $self->{MANIFOUND} = \@manifind;
  my $dist = $self->{DIST};
  unless (@manifind){
    $self->verbose(1,"NO FILES! in dist $dist?");
    return;
  }
  $self->verbose(1,"Found $manifound files in dist $dist, first $manifind[0]\n");
}

# package PAUSE::dist;
sub extract_readme_and_yaml {
  my $self = shift;
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
    $self->verbose(1,"No readme in $dist\n");
  }
  my $json = List::Util::reduce { length $a < length $b ? $a : $b }
             grep !m|/t/|, grep m|/META\.json$|, @manifind;
  my $yaml = List::Util::reduce { length $a < length $b ? $a : $b }
             grep !m|/t/|, grep m|/META\.yml$|, @manifind;

  unless ($json || $yaml) {
    $self->{METAFILE} = "No META.yml or META.json found";
    $self->verbose(1,"No META.yml or META.json in $dist");
    return;
  }

  for my $metafile ($json || $yaml) {
    if (-s $metafile) {
      $self->{METAFILE} = $metafile;
      File::Copy::copy $metafile, "$MLROOT/$sans.meta";
      utime((stat $metafile)[8,9], "$MLROOT/$sans.meta");
      PAUSE::newfile_hook("$MLROOT/$sans.meta");
      my $ok = eval {
        $self->{META_CONTENT} = Parse::CPAN::Meta->load_file($metafile); 1
      };
      unless ($ok) {
        $self->verbose(1,"Error while parsing $metafile: $@");
        $self->{META_CONTENT} = {};
        $self->{METAFILE} = "$metafile found but error "
                          . "encountered while loading: $@";
      }
    } else {
      $self->{METAFILE} = "Empty $metafile found, ignoring\n";
    }
  }
}

# package PAUSE::dist
sub version_from_meta_ok {
  my($self) = @_;
  return $self->{VERSION_FROM_META_OK} if exists $self->{VERSION_FROM_META_OK};
  my $c = $self->{META_CONTENT};

  # If there's no provides hash, we can't get our module versions from the
  # provides hash! -- rjbs, 2012-03-31
  return($self->{VERSION_FROM_META_OK} = 0) unless $c->{provides};

  # Some versions of Module::Build geneated an empty provides hash.  If we're
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

# package PAUSE::dist
sub verbose {
  my($self,$level,@what) = @_;
  my $main = $self->{MAIN};
  $main->verbose($level,@what);
}

# package PAUSE::dist
sub lock {
  my($self) = @_;
  if ($self->{'SKIP-LOCKING'}) {
    $self->verbose(1,"Forcing indexing without a lock");
    return 1;
  }
  my $dist = $self->{DIST};
  my $dbh = $self->connect;
  my $rows_affected = $dbh->do(
    "UPDATE distmtimes SET indexing_at=?
    WHERE dist='$dist'
      AND indexing_at IS NULL",
    undef,
    PAUSE->_now_string,
  );
  return 1 if $rows_affected > 0;
  my $sth = $dbh->prepare("SELECT * FROM distmtimes WHERE dist=?");
  $sth->execute($dist);
  if ($sth->rows) {
    my $row = $sth->fetchrow_hashref();
    require Data::Dumper;
    $self->verbose(1,
      sprintf(
        "Cannot get lock, current record is[%s]",
        Data::Dumper->new([$row],
          [qw(row)],
        )->Indent(1)->Useqq(1)->Dump,
      ));
  } else {
    $self->verbose(1,"Weird: first we get no lock, then the record is gone???");
  }
  return;
}

# package PAUSE::dist
sub set_indexed {
  my($self) = @_;
  my $dist = $self->{DIST};
  my $dbh = $self->connect;
  my $rows_affected = $dbh->do(
    "UPDATE distmtimes SET indexed_at=?  WHERE dist='$dist'",
    undef,
    PAUSE->_now_string,
  );
  $rows_affected > 0;
}

1;

