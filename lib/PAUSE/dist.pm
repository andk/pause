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
use JSON::XS ();

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
# But we need to refuse indexing of bleadperls too: for duallife
# modules.
# 2013-04-14: no longer used, but left commented out in case we change
# our minds -- xdg, 2013-04-14
##our $ISA_BLEAD_PERL = qr{
##    /
##    perl-5\.\d*[13579]\.\d+
##    (?: \.tar\.gz
##    |   \.tar\.bz2
##    )
##    \z
##}x;


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
  $dbh->do("DELETE FROM packages WHERE dist=?", undef, $dist);
  $dbh->do("DELETE FROM distmtimes WHERE dist=?", undef, $dist);
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
    if (m:^[^/]+/META6\.json$:m) {
        $self->{PERL_MAJOR_VERSION} = 6
    }
  }
  $self->{PERL_MAJOR_VERSION} = 5 unless defined $self->{PERL_MAJOR_VERSION};
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
sub perl_major_version { shift->{PERL_MAJOR_VERSION} }

# package PAUSE::dist;
sub skip { shift->{SKIP} }

sub isa_regular_perl {
  my($self,$dist) = @_;
  scalar $dist =~ /$PAUSE::dist::ISA_REGULAR_PERL/;
}

# Commented out this function just like $ISA_BLEAD_PERL
##sub isa_blead_perl {
##  my($self,$dist) = @_;
##  scalar $dist =~ /$PAUSE::dist::ISA_BLEAD_PERL/;
##}

# should use CPAN::DistnameInfo but note: "zip" not contained
# because it is special-cased below
my $SUFFQR = qr/\.(tgz|tbz|tar[\._-]gz|tar\.bz2|tar\.Z)$/;

sub _examine_regular_perl {
  my ($self) = @_;
  my ($suffix, $skip);

  my $dist = $self->{DIST};

  my($u) = PAUSE::dir2user($dist); # =~ /([A-Z][^\/]+)/; # XXX dist2user

  my $has_pumpking_bit = PAUSE->user_has_pumpking_bit($u);

  if ($has_pumpking_bit){
    $skip = 0;
    $self->verbose(1,"Perl dist $dist from trusted user $u");
  } else {
    $skip = 1;
    $self->verbose(1,"*** ALERT: Perl dist $dist from untrusted user $u. Skip set to [$skip]\n");
  }

  if ($dist =~ $SUFFQR) {
    $suffix = $1;
  } else {
    $self->verbose(1,"A perl distro ($dist) with an unusual suffix!\n");
    $self->alert("A perl distro ($dist) with an unusual suffix!");
  }
  unless ($skip) {
    $skip = 1 unless $self->untar;
  }

  return ($suffix, $skip);
}

sub isa_dev_version {
  my ($self) = @_;
  my $dist = $self->{DIST};

  return $dist =~ /\d\.\d+_\d/ || $dist =~ /-TRIAL[0-9]*$SUFFQR/;
}

# package PAUSE::dist;
sub examine_dist {
  my($self) = @_;
  my $dist = $self->{DIST};
  my $MLROOT = $self->mlroot;
  my($suffix,$skip);
  $suffix = $skip = "";

  if ($self->isa_regular_perl($dist)) {
    ($suffix, $skip) = $self->_examine_regular_perl;
    $self->{SUFFIX} = $suffix;
    $self->{SKIP}   = $skip;
    return;
  }

  if ($self->isa_dev_version) {
    $self->verbose(1,"Dist '$dist' is a developer release\n");
    $self->{SUFFIX} = "N/A";
    $self->{SKIP}   = 1;
    return;
  }

  if ($dist =~ m|/perl-\d+|) {
    $self->verbose(1,"Dist '$dist' is an unofficial perl-like release\n");
    $self->{SUFFIX} = "N/A";
    $self->{SKIP}   = 1;
    return;
  }

  if ($dist =~ $SUFFQR) {
    $suffix = $1;
    $skip = 1 unless $self->untar;
  } elsif ($dist =~ /\.pm\.(?:Z|gz|bz2)$/) {
    $self->verbose(1,"Dist '$dist' is a single-.pm-file upload\n");
    $suffix = "N/A";
    $skip   = 1;
    $self->{SKIP_REPORT} = PAUSE::mldistwatch::Constants::EBAREPMFILE;
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

  push @m,
    "The following report has been written by the PAUSE namespace indexer.\n",
    "Please contact modules\@perl.org if there are any open questions.\n";

  if ($self->has_indexing_warnings) {
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
  my $versions_from_meta = $self->version_from_meta_ok ? "yes" : "no";
  my $parse_cpan_meta_version = Parse::CPAN::Meta->VERSION;

  # This can occur when, for example, the "distribution" is Foo.pm.gz — of
  # course then there is no README or META.*! -- rjbs, 2014-03-15
  my $readme   = $self->{README} // "(none)";
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

  if (my $err = $self->{SKIP_REPORT}) {
    push @m, $tf->format( PAUSE::mldistwatch::Constants::heading($err) ),
             qq{\n\n};
    $status_over_all = "Failed";
  }

  # NO_DISTNAME_PERMISSION must not hide other problem messages, so
  # we fix up any "OK" status records to reflect the permission
  # problem and let the rest of the report run as usual
  if ($self->{NO_DISTNAME_PERMISSION}) {
    my $pkg = $self->_package_governing_permission;
    push @m, $tf->format(qq[This distribution name will only be indexed
      when uploaded by users with permission for the package $pkg.
      Either someone else has ownership over that package name, or
      this is a brand new distribution and that package name was neither
      listed in the 'provides' field in the META file nor found
      inside the distribution's modules.  Therefore, no modules
      will be indexed.]);
    push @m, qq{\n\nFurther details on the indexing attempt follow.\n\n};
    $status_over_all = "Failed";

    my $inxst = $self->{INDEX_STATUS};
    if ($inxst && ref $inxst && %$inxst) {
      unless ($inxst->{$pkg}) {
        # Perhaps they forgot a pm file matching the dist name
        push @m, $tf->format(qq{\n\nYou appear to be missing a .pm file
           containing a package matching the dist name ($pkg). Adding this
           may solve your issue.}) . "\n";
      }

      for my $p ( keys %$inxst ) {
          next unless
            $inxst->{$p}{status} == PAUSE::mldistwatch::Constants::OK;
          $inxst->{$p}{status} = PAUSE::mldistwatch::Constants::EDISTNAMEPERM;
          $inxst->{$p}{verb_status} =
            "Not indexed; $author not authorized for this distribution name";
      }
    }
    else {
        # some other problem prevented any modules from having status
        # recorded, we don't have to do anything
    }
  }

  if ($self->{HAS_MULTIPLE_ROOT}) {

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
      being indexed: @{$self->{HAS_WORLD_WRITABLE}} ]);

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
          push @m, sprintf "Status: %s\n%s\n\n", $heading, "="x(length($heading)+8);
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
        push @m, sprintf("     module : %s\n",  $p);

        if (my @warnings = $self->indexing_warnings_for_package($p)) {
          push @m, map {;
                 sprintf("     WARNING: %s\n", $_) } @warnings;
        }

        push @m, sprintf("     version: %s\n", $inxst->{$p}{version});
        push @m, sprintf("     in file: %s\n", $inxst->{$p}{infile});
        push @m, sprintf("     status : %s\n",  $verb_status);

        $Lstatus = $status;
      }
    } else {
      $self->verbose(1,
        sprintf "st[%s]\n", (Data::Dumper::Dumper($inxst) =~ s/\v+\z//r)
      );
      if ($pmfiles > 0 || $self->{SKIP_REPORT}) {
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

sub add_indexing_warning {
  my($self,$pack,$warning) = @_;

  push @{ $self->{INDEX_WARNINGS}{$pack} }, $warning;
  return;
}

sub indexing_warnings_for_package {
  my($self,$pack) = @_;
  return @{ $self->{INDEX_WARNINGS}{$pack} // [] };
}

sub has_indexing_warnings {
  my ($self) = @_;
  my $i;
  my $warnings = $self->{INDEX_WARNINGS};

  @$_ && return 1 for values %$warnings;
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

sub _package_governing_permission {
  my $self = shift;

  my $d = CPAN::DistnameInfo->new($self->{DIST});
  my $dist_name = $d->dist;
  (my $main_pkg = $dist_name) =~ s/[-+]+/::/g;

  return $main_pkg;
}

sub _index_by_files {
  my ($self, $pmfiles, $provides) = @_;
  my $dist = $self->{DIST};

  my $binary_dist;
  # ftp://ftp.funet.fi/pub/CPAN/modules/05bindist.convention.html
  $binary_dist = 1 if $dist =~ /\d-bin-\d+-/i;
  my $main_package = $self->_package_governing_permission;

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
      MAIN_PACKAGE => $main_package,
    );
    $fio->examine_fio;
  }
}

sub _index_by_meta {
  my ($self, $pmfiles, $provides) = @_;
  my $dist = $self->{DIST};

  my $main_package = $self->_package_governing_permission;

  my @packages =  map {[ $_ => $provides->{$_ }]} sort keys %$provides;
  for (@packages) {
    my ( $k, $v ) = @$_;
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
      MAIN_PACKAGE => $main_package,
    );
    $pio->examine_pkg;
  }
}

# package PAUSE::dist;
sub examine_pms {
  my $self = shift;
  return if $self->{HAS_BLIB};
  return if $self->{HAS_MULTIPLE_ROOT};
  return if $self->{HAS_WORLD_WRITABLE};

  # XXX not yet reached, we need to re-examine what happens without SKIP.
  # Currently SKIP shadows the event of could_not_untar
  return if $self->{COULD_NOT_UNTAR};

  my $dist = $self->{DIST};

  my $pmfiles = $self->filter_pms;
  my ($meta, $provides, $indexing_method);

  if (my $version_from_meta_ok = $self->version_from_meta_ok) {
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
    $self->$indexing_method($pmfiles, $provides);
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

  my @manifind;
  my $ok = eval { @manifind = sort keys %{ExtUtils::Manifest::manifind()}; 1 };
  $self->{MANIFOUND} = \@manifind;
  unless ($ok) {
    $self->verbose(1,"Errors in manifind: $@");
    return;
  }

  my $manifound = @manifind;
  my $dist = $self->{DIST};
  unless (@manifind){
    $self->verbose(1,"NO FILES! in dist $dist?");
    return;
  }
  $self->verbose(1,"Found $manifound files in dist $dist, first $manifind[0]\n");
}

# package PAUSE::dist;
sub extract_readme_and_meta {
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
    $self->verbose(1,"No META.yml or META.json in $dist");
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

sub write_updated_meta6_json {
  my($self, $metafile, $MLROOT, $dist, $sans) = @_;

  my $json = JSON::XS->new->utf8->canonical->pretty;

  open my $meta_fh, '<', $metafile
    or $self->verbose(1,"Failed to open META6.json file for reading $!");
  my $meta = eval {
    $json->decode(join '', <$meta_fh>);
  };
  if ($@) {
    $self->verbose(1,"Failed to parse META6.json file: $@");
    File::Copy::copy $metafile, "$MLROOT/$sans.meta";
    return;
  }
  close $meta_fh;

  $meta->{'source-url'} = $PAUSE::Config->{PUB_MODULE_URL} . $dist;

  open $meta_fh, '>', "$MLROOT/$sans.meta"
    or $self->verbose(1,"Failed to open Perl 6 meta file for writing: $!");
  print { $meta_fh } $json->encode($meta)
    or $self->verbose(1,"Failed to write Perl 6 meta file: $!");
  close $meta_fh;
}

# package PAUSE::dist
sub version_from_meta_ok {
  my($self) = @_;
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

# package PAUSE::dist
sub verbose {
  my($self,$level,@what) = @_;
  PAUSE->log($self, $level, @what);
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
    WHERE dist=?
      AND indexing_at IS NULL",
    undef,
    PAUSE->_now_string,
    $dist,
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
    "UPDATE distmtimes SET indexed_at=?  WHERE dist=?",
    undef,
    PAUSE->_now_string,
    $dist,
  );
  $rows_affected > 0;
}

# package PAUSE::dist
sub p6_dist_meta_ok {
  my $self = shift;
  my $c    = $self->{META_CONTENT};
  $c &&
  $c->{name} &&
  $c->{version} &&
  $c->{description}
}

# package PAUSE::dist
sub p6_index_dist {
  my $self   = shift;
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
  $self->verbose(1,
    sprintf("Inserted into p6dists name[%s]auth[%s]ver[%s]tarball[%s]ret[%s]err[%s]\n", @args));

  return "ERROR in dist $dist: " . $dbh->errstr unless $ret;

  ###
  # Index provides section. This section is allowed to be empty or absent, in case this
  # distribution is about binaries or shared files.
  for my $namespace (keys %{$c->{provides} // {}}) {
    @args = ($namespace, $dist);
    $ret  = $dbh->do($p6provides, undef, @args);
    push @args, (defined $ret ? '' : $dbh->errstr), ($ret || '');
    $self->verbose(1,
      sprintf("Inserted into p6provides name[%s]tarball[%s]ret[%s]err[%s]\n", @args));
  }
  return "ERROR in dist $dist: " . $dbh->errstr unless $ret;

  ###
  # Index binaries. We need to scan the archives content for this.
  local *TARTEST;
  my $tarbin = $self->{TARBIN};
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
      $self->verbose(1,
        sprintf("Inserted into p6binaries name[%s]tarball[%s]ret[%s]err[%s]\n", @args));
    }
  }
  unless (close TARTEST) {
    $self->verbose(1,"Could not untar $dist!\n");
    $self->alert("\nCould not untar $dist!\n");
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
    MAIN   => $self,
    DIST   => $dist,
    DBH    => $dbh,
    ALERT  => "",
    TIME   => $time,
    TARBIN => $self->{TARBIN},
    UNZIPBIN  => $self->{UNZIPBIN},
    PICK   => $self->{PICK},
    'SKIP-LOCKING'  => $self->{'SKIP-LOCKING'},
  );

=head1 DESCRIPTION

Encapsulates operations on a distro, either in the database, in a
(possibly compressed archive), or unpacked on disk.

=head2 Methods

=head3 new

Constructor.

=head3 examine_dist

Does these checks:

  $dio->isa_regular_perl
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

=head3 isa_regular_perl

=head3 _examine_regular_perl

=head3 isa_dev_version

=head3 connect

=head3 disconnect

=head3 mlroot

=head3 mail_summary

=head3 index_status

=head3 add_indexing_warning

=head3 indexing_warnings_for_package

=head3 has_indexing_warnings

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
