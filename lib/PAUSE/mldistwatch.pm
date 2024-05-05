# Some POD is after __END__
package PAUSE::mldistwatch;

use strict;
use version 0.47; # 0.46 had leading whitespace and ".47" problems

use PAUSE::Logger '$Logger';

use CPAN (); # only for CPAN::Version
use CPAN::Checksums 1.050; # 1.050 introduced atomic writing
use CPAN::DistnameInfo ();
use Cwd ();
use DBI;
use Data::Dumper ();
use DirHandle ();
use Dumpvalue ();
use DynaLoader ();
use Email::MIME;
use Email::Sender::Simple qw(sendmail);
use Exporter ();
use ExtUtils::MakeMaker ();
use ExtUtils::Manifest;
use Fcntl qw();
use File::Basename ();
use File::Copy ();
use File::pushd;
use File::Spec ();
use File::Temp 0.14 (); # begin of OO interface
use File::Which ();
use Git::Wrapper;
use HTTP::Date ();
use IPC::Cmd ();
use JSON ();
use List::Util ();
use List::MoreUtils ();
use Path::Class;
use PAUSE ();
use PAUSE::dist ();
use PAUSE::pmfile ();
use PAUSE::package ();
use PAUSE::mldistwatch::Constants ();
use PAUSE::MailAddress ();
use PAUSE::PermsManager ();
use Process::Status ();
use Safe;
use Text::Format;

$Data::Dumper::Indent = 1;

# "MAIN" at the end of file to guarantee all packages are inintialized

use DB_File;
use Fcntl qw(O_RDWR O_CREAT);
use File::Find;
use File::Path qw(rmtree mkpath);
our $MAINTAIN_SYMLINKTREE = 1;

use Fcntl qw(:flock);
# this class shows that it was born as spaghetticode

# This can/should be replaced by making things like "reasons to skip indexing a
# dist" into an enumerated type.  Until that happens, though, this one needs to
# be easy to refer to, because it's compared against (search for the var name
# below). -- rjbs, 2024-04-28
my $OLD_UNCHANGED_FILE = "file mtime has not changed";

sub new {
    my $class = shift;
    my $opt = shift;

    my $fh;
    unless ($opt->{pick}) { # pick files shall not block full run
        my $pidfile = File::Spec->catfile( $PAUSE::Config->{PID_DIR}, 'mldistwatch.pid');
        if (open $fh, "+>>", $pidfile) {
            if (flock $fh, LOCK_EX|LOCK_NB) {
                truncate $fh, 0 or die;
                seek $fh, 0, 0;
                my $ofh = select $fh;
                $|=1;
                print $fh $$, "\n";
                select $ofh;
            } elsif ($opt->{"fail-silently-on-concurrency-protection"}) {
                exit;
            } else {
                die "other mldistwatch job running, ".
                    "will not run at the same time";
            }
        } else {
            die "Could not open pidfile[$pidfile]: $!";
        }
    }

    my $tarbin = File::Which::which('tar');
    die "No tarbin found" unless -x $tarbin;

    my $unzipbin = File::Which::which('unzip');
    die "No unzip found" unless -x $unzipbin;

    my $self = bless {
                      TARBIN => $tarbin,
                      UNZIPBIN  => $unzipbin,
                      OPT => $opt,
                      PIDFH => $fh,
                     }, $class;
    $self->{VERBOSE} = -t STDOUT ? 2 : 1;
    if ($opt->{pick}) {
        for my $pick (@{$opt->{pick}}) {
            $pick =~ s|^.*authors/id/|| if $pick =~ m|authors/id/./../|;
            $self->{PICK}{$pick} = 1;
        }
    }
    if ($opt->{'skip-locking'}) {
        $self->{'SKIP-LOCKING'} = 1;
    }
    $Logger->log("PAUSE::mldistwatch object created");
    $self;
}

sub sleep {
    my($self) = @_;
    my $sleep = $self->{OPT}{sleep} //= 1;
    sleep $sleep;
}

sub reindex {
    my $self = shift;
    my $startdir = Cwd::cwd();
    my $MLROOT = $self->mlroot;
    chdir $MLROOT
        or die "Couldn't chdir to $MLROOT";

    $self->connect;

    $self->init_all();

    $Logger->log_debug("registering new users");
    $self->set_ustatus_to_active();

    my $testdir = File::Temp::tempdir(
                                      "mldistwatch_work_XXXX",
                                      DIR => "/tmp",
                                      CLEANUP => 0,
                                     ) or die "Could not make a tmp directory";
    chdir $testdir
        or die("Couldn't change to $testdir: $!");
    $self->check_for_new($testdir);
    chdir $startdir or die "Could not chdir to '$startdir'";
    rmtree $testdir;
    return if $self->{OPT}{pick};
    $self->rewrite_indexes;

    $self->disconnect;
}

sub permissions {
    my $self = shift;
    return $self->{PERM_MGR} if $self->{PERM_MGR};
    $self->{PERM_MGR} = PAUSE::PermsManager->new( dbh_callback => sub { $self->connect } );
}

sub rewrite_indexes {
    my $self = shift;

    $self->git->reset({ hard => 1 })
      if -e dir($self->gitroot)->file(qw(.git refs heads master));

    $self->rewrite02();
    my $MLROOT = $self->mlroot;
    chdir $MLROOT
        or die "Couldn't chdir to $MLROOT: $!";
    $self->rewrite01();
    $self->rewrite03();
    $self->rewrite06();
    $Logger->log("finished rewriting indexes");

    $self->git->commit({ m => "indexer run at $^T, pid $$" })
        if $self->git->status->is_dirty;
}

sub debug_mem {
    my($self) = @_;
    return unless $self->{OPT}{debug_mem};
    my @caller = caller;
    open my $ps, "ps -o pid,vsize -p $$ |";
    open my $log, ">>", "/tmp/debug_mem.log" or die;
    print $log scalar localtime, "\n";
    print $log $caller[2], "\n";
    print $log +<$ps>;
    close $log or die;
}

sub filter_dups {
    my($self,$array) = @_;
    my($fh) = File::Temp->new(
                              DIR => "/tmp",
                              TEMPLATE => "mldistwatch_filterdups_XXXX",
                             );
    print $fh map {"$_\n"} @$array;
    close $fh;
    my $filename = $fh->filename;
    #system "wc -l $filename";
    system "sort --output=$filename --unique $filename";
    #system "wc -l $filename";
    open $fh, $filename;
    local $/ = "\n";
    @$array = <$fh>;
    #warn sprintf "scalar \@\$array: %d", scalar @$array;
    #warn "Press RET to continue";
    #<>;
    chomp @$array;
    return;
}

sub set_ustatus_to_active {
    my $self = shift;
    my $db = $self->connect;
    my $active = $db->selectall_hashref("SELECT userid
                                         FROM users
                                         WHERE ustatus='active'",
                                        "userid");
    my %seen;
    $self->debug_mem;
    my @new_active_users;
    while (my $file = each %{$self->{ALLfound}}) {
        my($user) = $file =~ m|./../([^/]+)/|;
        unless (defined $user){
            $Logger->log("Warning: $file: could not determine user");
            next;
        }
        next if exists $active->{$user};
        push @new_active_users, $user;
    }
    $self->filter_dups(\@new_active_users);
    $self->debug_mem;
    return unless @new_active_users;

    $Logger->log_debug([ "marking users active: %s", \@new_active_users ]);

    my $sth = $db->prepare(
      "UPDATE users
      SET ustatus='active', ustatus_ch=?
      WHERE ustatus<>'nologin' AND userid=?"
    );

    for my $user (@new_active_users) {
        $sth->execute(PAUSE->_now_string, $user);
    }

    $sth->finish;
}

sub connect {
    my $self = shift;
    return $self->{DBH} if $self->{DBH};
    my $dbh = PAUSE::dbh("mod");
    $self->{DBH} = $dbh;
}

sub disconnect {
    my $self = shift;
    return unless $self->{DBH};
    $self->{DBH}->disconnect;
    delete $self->{PERM_MGR};
    delete $self->{DBH};
}

sub init_all {
    my $self = shift;
    $Logger->log_debug("running manifind");
    $self->{ALLfound} = $self->manifind;
    $Logger->log_debug("collecting distmtimes from database");
    $self->{ALLlasttime} = $self->dbfind;
}

sub dbfind {
    my($self) = @_;
    my %found;
    my($fh) = File::Temp->new(
                              DIR => "/tmp",
                              TEMPLATE => "mldistwatch_dbfind_XXXX",
                             );
    tie %found, 'DB_File', $fh->filename, O_RDWR|O_CREAT, 0644, $DB_HASH;
    my $dbh = $self->connect;
    my $sth = $dbh->prepare("SELECT dist, distmtime FROM distmtimes");
    $sth->execute;
    my($dist,$distmtime);
  RECORD: while (($dist,$distmtime) = $sth->fetchrow_array) {
        if ($self->{PICK}){
            my $hit;
            for my $pd (keys %{$self->{PICK}}) {
                $hit++ if $pd eq $dist;
            }
            next RECORD unless $hit;
        }
        $found{$dist} = $distmtime;
    }
    $sth->finish;
    \%found;
}

sub clean_up_filename {
    my($self,$filename) = @_;
    $filename =~ s|^\./||;
    return $filename;
}

sub manifind {
    my($self) = @_;
    my %found;
    return $self->{PICK} if $self->{PICK};
    my($fh) = File::Temp->new(
                              DIR => "/tmp",
                              TEMPLATE => "mldistwatch_manifind_XXXX",
                             );

    my $wanted = sub {
        return if m|CHECKSUMS$|;
        return if -d $_;
        my $name = $self->clean_up_filename($File::Find::name);
        $found{$name} = undef;
    };
    find(
         {wanted => $wanted},
         "."
        );

    return \%found;
}

sub _newcountokay {
  my ($self, $count) = @_;
  my $MIN = $PAUSE::Config->{ML_MIN_FILES};
  return $count >= $MIN;
}

sub _do_the_database_work {
  my ($self, $dio) = @_;

  my $ok = eval {
    # This is here for test purposes.  It lets us force the db work to die,
    # which should trigger a retry. -- rjbs, 2018-04-19
    if ($PAUSE::Config->{PRE_DB_WORK_CALLBACK}) {
      $PAUSE::Config->{PRE_DB_WORK_CALLBACK}->($dio);
    }

    my $dbh = $self->connect;
    unless ($dbh->begin_work) {
      $Logger->log("couldn't begin transaction!");
      return 1;
    }

    # Either we're doing Perl 6...
    if ($dio->perl_major_version == 6) {
      if ($dio->p6_dist_meta_ok) {
        if (my $err = $dio->p6_index_dist) {
          $dio->alert($err);
          $dbh->rollback;
        } else {
          $dbh->commit;
        }
      }
      else {
        $dio->alert("Meta information of Perl 6 dist is invalid");
        $dbh->rollback;
      }

      return 1;
    }

    # ...or else Perl 5...
    $dio->examine_pms;      # will switch user

    my $main_pkg = $dio->_package_governing_permission;

    if ($self->permissions->userid_has_permissions_on_package($dio->{USERID}, $main_pkg)) {
      $dio->normalize_package_casing;

      $dbh->commit;
    } else {
      $dio->alert("Uploading user has no permissions on package $main_pkg");
      $dio->{NO_DISTNAME_PERMISSION} = 1;
      $dbh->rollback;
    }

    return 1;
  };

  my $err = $@;

  # Remember, $ok here only means "did the db work complete," not "did we
  # successfully index stuff." -- rjbs, 2018-04-19
  if ( !$ok ) {
    # Rethrow any errors that weren't from the database
    die $err if $err && ref($err) ne 'PAUSE::DBError';

    # $err should have a value if !$ok, but just in case not
    $err ||= "unknown error";
    $Logger->log_debug("error with database work: $err");
  }

  return $ok;
}

sub reason_to_skip_dist {
    my ($self, $dio) = @_;

    my $dist = $dio->{DIST};

    if (my $reason = $dio->ignoredist) {
      return $reason;
    }

    unless (exists $self->{ALLfound}{$dist}) {
        $dio->delete_goner;
        return "it's a goner";
    }

    unless ($dio->mtime_ok($self->{ALLlasttime}{$dist})){
        return $OLD_UNCHANGED_FILE;
    }

    unless ($dio->lock) {
        return "could not obtain a lock";
    }

    return;
}

sub maybe_index_dist {
    my ($self, $dist) = @_;

    my $dio = PAUSE::dist->new(
                               HUB    => $self,
                               DIST   => $dist,
                              );

    local $Logger = $Logger->proxy({ proxy_prefix => "$dist: " });

    if (my $skip_reason = $self->reason_to_skip_dist($dio)) {
        # We don't log on a few things that are extremely common and lead to
        # noise in the logs. -- rjbs, 2024-04-28
        my $log_method = $skip_reason eq $OLD_UNCHANGED_FILE ? 'log_debug'
                       : $skip_reason eq "non-dist file"     ? 'log_debug'
                       :                                       'log';
        $Logger->$log_method("skipping: $skip_reason");

        delete $self->{ALLlasttime}{$dist};
        delete $self->{ALLfound}{$dist};
        return;
    }

    $Logger->log("beginning examination");
    $0 = "mldistwatch: $dist";

    # >99% of all distros are already registered by the
    # newfilehook but the few coming though mirror(1) are not.
    # Registering *everything* that comes here should catch them
    # and if we re-register this or that it should not hurt. But
    # everything older than a day does not belong here, like when
    # people re-index an old distro.
    {
        my $MLROOT = $self->mlroot;
        for my $f ("$MLROOT/$dist") {
            local $^T = time;
            if (-M $f < 1) {
                PAUSE::newfile_hook($f);
            }
        }
    }

    for my $method (qw( examine_dist read_dist extract_readme_and_meta )) {
      $dio->$method;
      if ($dio->skip) {
          delete $self->{ALLlasttime}{$dist};
          delete $self->{ALLfound}{$dist};

          if ($dio->{REASON_TO_SKIP}) {
              $dio->mail_summary;
          }
          return;
      }
    }

    if ($dio->{META_CONTENT}{distribution_type}
        && $dio->{META_CONTENT}{distribution_type} =~ m/^(script)$/) {
        return;
    }

    if (($dio->{META_CONTENT}{release_status} // 'stable') ne 'stable') {
        # META.json / META.yml declares it's not stable; do not index!
        $dio->{REASON_TO_SKIP} = PAUSE::mldistwatch::Constants::EMETAUNSTABLE;
        $dio->mail_summary;
        return;
    }

    $dio->check_blib;
    $dio->check_multiple_root;
    $dio->check_world_writable;

    for my $attempt (1 .. 3) {
      my $db_ok = $self->_do_the_database_work($dio);
      last if $db_ok;
      $self->disconnect;
      if ($attempt == 3) {
        $Logger->log_debug("tried $attempt times to do db work, but all failed");
        $dio->alert("database errors while indexing");
        $dio->{REASON_TO_SKIP} = PAUSE::mldistwatch::Constants::E_DB_XACTFAIL;
      }
    }

    $dio->mail_summary unless $dio->perl_major_version == 6;
    $self->sleep;
    $dio->set_indexed;

    my @alerts = $dio->all_alerts;
    return unless @alerts;
    return @alerts;
}

sub check_for_new {
    my($self,$testdir) = @_;
    local $/ = "";
    my $dbh = $self->connect;
    my @all;
    my($fh) = File::Temp->new(
                              DIR => "/tmp",
                              TEMPLATE => "mldistwatch_all_XXXX",
                              UNLINK=>1,
                             );
    tie @all, 'DB_File', $fh->filename, O_RDWR|O_CREAT, 0644, $DB_RECNO or die;
    {
        $self->debug_mem;
        my %seen;
        @all = keys %{$self->{ALLfound}};
        push @all, keys %{$self->{ALLlasttime}};
        $self->filter_dups(\@all);
        $self->debug_mem;
    }

    my $all = scalar @all;

    die "Panic: unusual small number of files involved ($all)"
        if !$self->{PICK} && ! $self->_newcountokay($all);

    unless (@all) {
      $Logger->log_debug("BIGLOOP: no files to process!");
      return;
    }

    $Logger->log_debug("BIGLOOP: will process $all files");

    my %alerts;
  BIGLOOP: for (my $i=0;scalar @all;$i++, $self->empty_dir($testdir)) {
        my $dist = shift @all;

        $Logger->log_debug("BIGLOOP: [$i/$all] $dist") if $i%256 == 0;

        my @alerts = $self->maybe_index_dist($dist);
        $alerts{ $dist } = \@alerts if @alerts;
    }

    untie @all;
    undef $fh;

    $self->handle_alerts(\%alerts);
}

sub handle_alerts {
    my ($self, $alerts) = @_;

    return unless keys %$alerts;

    if ($PAUSE::Config->{TESTHOST} || $self->{OPT}{testhost}) {
      $Logger->log([ "sending alerts for %s", [ keys %$alerts ] ]);
      return;
    }

    my $body_str = "# Errors when processing new files\n\n";

    for my $dist (sort keys %$alerts) {
      next unless @{ $alerts->{$dist} }; # Should never happen. -- rjbs

      $body_str .= "$dist\n";
      for my $alert (@{ $alerts->{$dist} }) {
        $alert =~ s/^/  /mg;
        $alert =~ s/\A /-/;
        $body_str .= "$alert\n";
      }
      $body_str .= "\n";
    }

    my $email = Email::MIME->create(
        header_str => [
            To      => $PAUSE::Config->{ADMIN},
            Subject => "PAUSE upload indexing error",
            From    => "PAUSE <$PAUSE::Config->{UPLOAD}>",
        ],
        attributes => {
            charset      => 'utf-8',
            content_type => 'text/plain',
            encoding     => 'quoted-printable',
        },
        body_str => $body_str,
    );

    sendmail($email);

    return;
}

sub empty_dir {
    my($self,$testdir) = @_;
    chdir $testdir or die "Could not chdir to '$testdir': $!"; # reassure
    my($dh) = DirHandle->new(".");
    for my $dirent ($dh->read) {
        next if $dirent eq "." || $dirent eq "..";
        rmtree $dirent;
    }
    $dh->close;
}

sub _install {
  my ($self, $src) = @_;

  my @hunks  = File::Spec->splitdir($src);
  my $fn     = $hunks[-1];
  my $MLROOT = $self->mlroot;
  my $target = "$MLROOT/../../modules/$fn";
  my $temp   = "$target.new";

  unless (File::Copy::copy($src, $temp)) {
    $Logger->log([
      "couldn't copy: %s",
      { src => $src, dst => $temp, err => "$!" },
    ]);
  }

  rename $temp, $target
      or die "error renaming $target.new to $target: $!";
}

sub rewrite02 {
    my $self = shift;
    #
    # Rewriting 02packages.details.txt
    #
    $Logger->log("rewriting 02packages");

    my $dbh = $self->connect;
    my $MLROOT = $self->mlroot;
    my $repfile = "$MLROOT/../../modules/02packages.details.txt";
    my $list = "";
    my $olist = "";
    local($/) = "\n";
    our $GZIP = $PAUSE::Config->{GZIP_PATH};
    if (
        -f "$repfile.gz" and
        open my $fh, "$GZIP --stdout --uncompress $repfile.gz|"
       ) {
        while (<$fh>) {
            next if 1../^$/;
            $olist .= $_;
        }
        close $fh;
    }
    my $date = HTTP::Date::time2str();
    my $sth = $dbh->prepare(qq{SELECT package, version, dist, file
                               FROM packages
                               WHERE status='index'});
    # the status='noindex' is there so we can manually disable
    # indexing of packages if need be (2004-05-04 we had such a case)
    $sth->execute;
    my(@row,@listing02);
    my $numrows = $sth->rows;
    $Logger->log_debug("number of indexed packages: $numrows");
    while (@row = $sth->fetchrow_array) {
        my($one,$two);
        my $infile = $row[0];
        $infile =~ s/^.+:://;
        next unless $row[3];
        # 2011-11-29: dropping the following sanity check after DHUNT
        # PDL::NetCDF 4.15: hidden sanity checks stop being plausible
        # when everybody has forgotten them.

        #next unless index($row[3],"$infile.pm")>=0
        #    or $row[3]=~/VERSION/i # VERSION is Russ Allbery's idea to
        #                           # force inclusion
        #        or $row[3] eq "missing in META.yml, tolerated by PAUSE indexer";
        $row[1] =~ s/^\+//;
        $one=30;
        $two=8;
        if (length($row[0])>$one) {
            $one += 8 - length($row[1]);
            $two = length($row[1]);
        }
        push @listing02, sprintf "%-${one}s %${two}s  %s\n", @row;
    }
    my $numlines = @listing02;

    die "Absurd small number of lines"
      unless $numlines >= $PAUSE::Config->{ML_MIN_INDEX_LINES};

    my $header = qq{File:         02packages.details.txt
URL:          http://www.cpan.org/modules/02packages.details.txt
Description:  Package names found in directory \$CPAN/authors/id/
Columns:      package name, version, path
Intended-For: Automated fetch routines, namespace documentation.
Written-By:   $PAUSE::Id
Line-Count:   $numlines
Last-Updated: $date\n\n};

    $list .= join "", sort {lc $a cmp lc $b} @listing02;
    if ($list ne $olist) {
        my $F;
        my $gitfile = File::Spec->catfile(
          $self->gitroot,
          '02packages.details.txt',
        );
        if (open $F, ">", $gitfile) {
            print $F $header;
            print $F $list;
        } else {
            $Logger->log("couldn't open $repfile for writing 02packages: $!");
        }
        close $F or die "Couldn't close: $!";
        $self->git->add({}, '02packages.details.txt');

        $self->_install($gitfile);

        PAUSE::newfile_hook($repfile);
        0==system "$GZIP $PAUSE::Config->{GZIP_OPTIONS} --stdout $repfile > $repfile.gz.new"
            or $Logger->log([ "couldn't gzip $repfile: %s", Process::Status->as_struct ]);
        rename "$repfile.gz.new", "$repfile.gz" or
            $Logger->log("couldn't rename to $repfile.gz: $!");
        PAUSE::newfile_hook("$repfile.gz");
    }
}

sub rewrite01 {
    my($self) = shift;
    #
    # Rewriting 01modules.index.html
    #
    $Logger->log_debug("entering rewrite01");
    my $dbh = $self->connect;

    my $MLROOT = $self->mlroot;
    my $repfile = "$MLROOT/../../modules/01modules.index.html";
    my $list = "";
    my $olist = "";
    local $/;
    if (-e $repfile) {
        if (open my $fh, $repfile) {
            while (<$fh>) {
                $olist .= $_;
            }
            close $fh;
        } else {
            $Logger->log("couldn't open $repfile $!");
        }
    } else {
        $Logger->log("no 01modules exist; won't try to read it");
    }
    my(%firstlevel,%achapter);
    my $sth = $dbh->prepare("SELECT modid, chapterid FROM mods");
    $sth->execute;
    while (my($modid,$chapterid) = $sth->fetchrow_array) {
        my($root,$colo) = $modid =~ /^([^:]+)(::)?/;
        $firstlevel{$root}++;
        # the determination of %achapter was introduced with rev 211.
        # Alternatives were tried in 212 and 214, but they had
        # uncountable misfits. 215 then was very similar to 211 but we
        # did sort above query by chapterid and got tons of misfits.
        # So we do not really have a solution. Every solution is
        # wrong, even the pre-211 solution. OK, I've taken out the
        # order by clause and retested, cheap_chapter deviates from
        # old chapter for Exception, Sort, and User, that's all.
        if ($colo) {
            if (! exists $achapter{$root}) {
                $achapter{"$root\::"} ||= $chapterid;
            }
        } else {
            delete $achapter{"$root\::"};
            $achapter{$root} ||= $chapterid;
        }
    }
    my(@chaptitle);
    $sth = $dbh->prepare("SELECT chapterid, shorttitle FROM chapters");
    $sth->execute;
    while (my($chapterid, $shorttitle) = $sth->fetchrow_array) {
        $chaptitle[$chapterid] = sprintf "%02d_%s", $chapterid, $shorttitle;
    }

    $sth = $dbh->prepare("SELECT package, dist FROM packages");
    $sth->execute;
    my(@listing01,%count);
    my $count = 0;
    my(%seen);

    my(%usercache,%userdircache,$i);
    my(@symlinklog);
 PACKAGE: while (my($pkg,$pkgdist) = $sth->fetchrow_array) {
        my %pkg = (rootpack => $pkg, dist => $pkgdist);
        $pkg{rootpack} =~ s/:.*//;
        # We don't want to list perl distribution
        next PACKAGE if $pkg{dist} =~ m|/perl-?5|;
        if ($seen{$pkg{dist},$pkg{rootpack}}++) {
            next PACKAGE;
        }
        if ($firstlevel{$pkg{rootpack}}) {
            #print "01 will have: $pkg{rootpack}/$pkg{dist}\n";
        } else {
            next PACKAGE;
        }

        $i++;
        @pkg{qw/size mtime/} =
            (stat "$MLROOT/$pkg{dist}")[7,9];
        next PACKAGE unless defined $pkg{size}; # somebody removed it while we were running
        $count++ unless $count{$pkg{dist}}++;
        $pkg{size} =
            $pkg{size} > 700000 ?
                sprintf "%.1fM", $pkg{size}/1024/1024 :
                    $pkg{size} > 700 ?
                        sprintf "%dk", $pkg{size}/1024+0.5 :
                            "1k";
        # my(@parts) = split /\//, $pkg{dist};
        my $directory = File::Basename::dirname($pkg{dist});
        my $user = $usercache{$directory} ||= PAUSE::dir2user($pkg{dist});
        my $f = File::Basename::basename($pkg{dist});
        my $userdir = $userdircache{$user} ||= PAUSE::user2dir($user);
        die "no user for dist[$pkg{dist}]" unless $user;
        # die "no user in database with id[$user]" unless $User{$user};
        $pkg{userid} = $user;
        # $pkg{fullname} = $User{$user};
        $pkg{userdir} = $userdir;
        $pkg{useridfiller} = " "x(10-length($user));
        $pkg{filenameonly} = $f;
        $pkg{filenamefiller} =
            " "x(38-length($f)-length($pkg{size}));
        $pkg{mtimestr} =
            substr(HTTP::Date::time2str($pkg{mtime}),5,11);
        $pkg{young} =
            $pkg{mtime} > $^T - 60 * 60 * 24 * 14 ? "  +" : "";

        push @listing01, [@pkg{qw/rootpack  userdir      userid         useridfiller
                                dist     filenameonly filenamefiller size
                                mtimestr young        mtime/}];

        # now the symlinks.
        # we just wrote something like
        # Sybase      MEWP   sybperl-2.03.tar.gz     91.8  31 Jan 1996
        # we are in authors/id/
        $pkg{rootpack} =~ s/\*$//; # XXX seems stemming from already deleted code
        {
            my $d = CPAN::DistnameInfo->new("authors/id/$pkg{dist}");
            my $exte = $d->extension;
            unless ($exte) {
                $Logger->log("Warning: undetermined extension on '$pkg{dist}'");
            }
            ($pkg{readme} = $pkg{dist}) =~
                s/\.\Q$exte\E/.readme/;
        }
        $pkg{readmefn} = File::Basename::basename($pkg{readme});

        $pkg{chapterid} = $achapter{$pkg{rootpack}}
            || $achapter{"$pkg{rootpack}\::"};

        if (defined $pkg{chapterid}) {
            if (defined $chaptitle[$pkg{chapterid}]) {
                $pkg{chapter} = $chaptitle[$pkg{chapterid}]
            } else {
                $pkg{chapter} = "99_Not_In_Modulelist";
                $Logger->log("found no chapterid for $pkg{rootpack}");
            }
        } else {
            $pkg{chapter} = "99_Not_In_Modulelist";
            $Logger->log("found no chapter for $pkg{rootpack}");
        }

        if ($MAINTAIN_SYMLINKTREE) {
            my $bymod = "$MLROOT/../../modules/".
                "by-module/$pkg{rootpack}/$pkg{filenameonly}";
            my $bycat = "$MLROOT/../../modules/".
                "by-category/$pkg{chapter}/$pkg{rootpack}/$pkg{filenameonly}";
            if ($self->{OPT}{symlinkinventory}) {
                # maybe once a day is enough
            } else {
                next PACKAGE if -e $bymod and -e $bycat;
            }

            $self->chdir_ln_chdir($MLROOT,
                                  "../../../authors/id/$pkg{dist}",
                                  "../../modules/by-module/$pkg{rootpack}".
                                  "/$pkg{filenameonly}",
                                  \@symlinklog,
                                 );
            $self->chdir_ln_chdir($MLROOT,
                                  "../../../authors/id/$pkg{readme}",
                                  "../../modules/by-module/$pkg{rootpack}".
                                  "/$pkg{readmefn}",
                                  \@symlinklog,
                                 )
                if -f $pkg{readme};
            $self->chdir_ln_chdir($MLROOT,
                                  "../../../authors/id/$userdir",
                                  "../../modules/by-module/$pkg{rootpack}/$pkg{userid}",
                                  \@symlinklog,
                                 );
            $self->chdir_ln_chdir($MLROOT,
                                  "../../../../authors/id/$pkg{dist}",
                                  "../../modules/by-category/$pkg{chapter}".
                                  "/$pkg{rootpack}/$pkg{filenameonly}",
                                  \@symlinklog,
                                 );
            $self->chdir_ln_chdir($MLROOT,
                                  "../../../../authors/id/$pkg{readme}",
                                  "../../modules/by-category/$pkg{chapter}".
                                  "/$pkg{rootpack}/$pkg{readmefn}",
                                  \@symlinklog,
                                 )
                if -f $pkg{readme};
            $self->chdir_ln_chdir($MLROOT,
                                  "../../../../authors/id/$userdir",
                                  "../../modules/by-category/$pkg{chapter}".
                                  "/$pkg{rootpack}/$pkg{userid}",
                                  \@symlinklog,
                                 );
        }
    }
    $Logger->log([ "symlinks updated: %d", 0+@symlinklog ]);
    {
        if ($self->{OPT}{symlinkinventory}
            and
            open my $fh, ">", "/var/run/mldistwatch-modules-symlinks.yaml") {
            print $fh YAML::Syck::Dump(\@symlinklog);
        }
    }
    $list = qq{<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Modules
on CPAN alphabetically</title></head><body>
<h1>CPAN\'s $count modules distributions</h1>
<h3>in alphabetical order by modules contained in the distributions</h3>
<i>} .
    scalar gmtime() .
        qq{ UTC</i>

<p>The list contains modules distribution files on CPAN for modules that
are <b>not</b> included in the perl standard distribution but
<b>are</b> included in the current release of <a
href="00modlist.long.html">Perl Module List</a>. To keep the size of
this list acceptable, it does not list which modules are in each
package. To get at those, it is recommended to use the CPAN.pm module
or read the detailed <a
href="02packages.details.txt.gz">listing</a>.</p>

<p>Column <b><code>module/category</code></b> contains the module or
category name, column <b><code>author/maintainer</code></b> the userid
of the author or maintainer which is a hyperlink to her homedirectory.
The filename in column <b><code>current distribution file</code></b>
is a link to the real file. The last column <b><code>young</code></b>
contains a plus sign if the file is younger than two weeks.</p>

<p><i>See also:</i></p>

<ul>

<li> <a href="01modules.mtime.html">Most recent uploads</a> sorted by uploadtime.</li>

<li> <a href="../CPAN.html">CPAN\'s <b>front page</b></a> by Jon Orwant.</li>

<li> <a href="00modlist.long.html">The <b>Module List</b></a>
by Tim Bunce and Andreas K&ouml;nig</li>

<li> <a href="../authors/00whois.html"><b>Who is who</b></a></li>

<li> The detailed <a href="02packages.details.txt.gz">listing</a> of all
packages found in these distribution files</li>

</ul>
<hr />
<pre>
module/     author/   current distribution file       size   uploaded   young
category    maintainer

};

#'
    $list .= join("",
                  map {sprintf(
                               qq{%-12s<a href="../authors/id/%s">%s</a>%s<a
 href="../authors/id/%s">%s</a> %s %s  %s%s\n},
                               @$_
                              )}
                  sort {lc $a->[0] cmp lc $b->[0] # package(root)
                            or
                                $a->[2] cmp $b->[2] # userid
                                    or
                                        lc $a->[5] cmp lc $b->[5] # filename
                                    } @listing01
                 );
    $list .= q{</pre></body></html>};

    my($comparelist) = $list;
    $comparelist =~ s/.+?<hr\b//s; # delete the intro (date!)
        $olist       =~ s/.+?<hr\b//s;

    if ($comparelist ne $olist) {
        if (open my $fh, ">$repfile.new") {
            print $fh $list;
            close $fh;
            rename "$repfile.new", $repfile or die;
            PAUSE::newfile_hook($repfile);
            $self->write_01sorted(\@listing01);
        } else {
            $Logger->log("couldn't open 01modules: $!");
        }
    }
}

sub xmlquote {
  my @x = @_;
  foreach my $it (@x) {
    $it = '' unless defined $it;
    $it =~ s<([^\n\r\t\x20\x21\x23\x27-\x3b\x3d\x3F-\x5B\x5D-\x7E])>
            <'&#'.(ord($1)).';'>seg;
      # turn strange things into decimal-numeric entities, no questions asked.
  }
  return join '', @x unless wantarray;
  return @x;
}

sub write_01sorted {
    my($self, $listing) = @_;
    my($n) = 150;

    my $html = qq{\n<html><head>
<title>Modules on CPAN sorted by upload date</title>
<link rel="alternate" type="application/rss+xml" title="RSS"
  href="./01modules.mtime.rss" />
</head>
<body>
<h1>CPAN\'s $n most recent uploads</h1>
<h3>ordered by timestamp of the distributions</h3>
A description of the list can be found in
<a href="01modules.index.html">01modules.index.html</a>.

  &#160;&#160;&#160;&#160;&#160;

<a href="./01modules.mtime.rss"
 style="
 border: 3px solid;
 border-color: #FC9 #630 #330 #F96;
 background: #F60;
 color: #FFF !important;
 margin: 0;
 padding: 0 3px;
 font: bold .7em verdana, sans-serif;
 text-decoration: none !important;
"
>RSS</a>

<hr />
<pre>
author/   distribution file                     size   uploaded
maintainer

};

    my $rss = qq{<?xml version="1.0"?>
<rss version="2.0"
  xmlns:sy="http://purl.org/rss/1.0/modules/syndication/"
><channel>
<title>Recent CPAN Uploads</title>
<description>The $n most recent modules uploaded to CPAN</description>
<link>http://www.cpan.org/modules/01modules.mtime.html</link>
<language>en</language>
<sy:updateFrequency>3</sy:updateFrequency>
<sy:updatePeriod>daily</sy:updatePeriod>
<sy:updateBase>1970-01-01T12:24+00:00</sy:updateBase>
<ttl>480</ttl>
<webMaster>cpan&#64;perl.org</webMaster>
};

    my(%seen);
    for my $l (
               sort {$b->[10] <=> $a->[10] # mtime
                 } @$listing
              ) {
        next if $seen{$l->[4]}++; # dist
        my %package;
        @package{qw{package userdir userid
                    useridfiller dist filenameonly
                    filenamefiller size mtimestr young mtime}}
            = xmlquote( @$l );

##   DB<2> x \%package
## 0  HASH(0x8c42664)
##    'dist' => 'W/WS/WSNYDER/SystemPerl-1.150.tar.gz'
##    'filenamefiller' => '            '
##    'filenameonly' => 'SystemPerl-1.150.tar.gz'
##    'mtime' => 1088685199
##    'mtimestr' => '01 Jul 2004'
##    'package' => 'SystemC'
##    'size' => '73k'
##    'userdir' => 'W/WS/WSNYDER'
##    'userid' => 'WSNYDER'
##    'useridfiller' => '   '
##    'young' => '  +'

        $package{filenamefiller} =
            " "x(40-length($package{filenameonly})-length($package{size}));
        $package{'useridpretty'} = ucfirst(
          $package{'useridlc'}   = lc $package{'userid'}
        );
        {
            my $d = CPAN::DistnameInfo->new("authors/id/$package{dist}");
            my $exte = $d->extension;
            ($package{basename}) =
                $package{filenameonly} =~ /^(.*)\.(?:\Q$exte\E)/;
        }
        $html .= sprintf(
                         qq{<a href="../authors/id/%s">%s</a>%s<a
 href="../authors/id/%s">%s</a> %s %s   %s\n},
                         @package{qw{userdir userid useridfiller dist filenameonly
                                     filenamefiller size mtimestr}}
                        );

        $rss .= sprintf qq{
<item>
  <title>%s : %s</title>
  <link>http://www.cpan.org/modules/by-authors/id/%s/%s</link>
  <description>%s uploaded %s (%s) on %s</description>
  <guid isPermaLink="false">%s</guid>
  <comments>http://search.cpan.org/~%s/%s/</comments>
</item>
},
                         @package{qw{basename useridpretty
                                     userdir filenameonly
                                     useridpretty dist size mtimestr
                                     filenameonly
                                     useridlc package
                                 }};

        last unless --$n;

    }
    $html .= qq{</pre></body></html>\n};
    $rss .= "\n</channel></rss>\n";

    my $MLROOT = $self->mlroot;

    my $rssfile = "$MLROOT/../../modules/01modules.mtime.rss";
    # $Logger->log("writing $rssfile");
    if (open my $F, ">", "$rssfile.new") {
        print $F $rss;
        close $F;
        rename "$rssfile.new", $rssfile or die;
        PAUSE::newfile_hook($rssfile);
    } else {
        die "Could not write-open >$rssfile:$!";
    }

    my $repfile = "$MLROOT/../../modules/01modules.mtime.html";
    # $Logger->log("writing $repfile");
    if (open my $F, ">", "$repfile.new") {
        print $F $html;
        close $F;
        rename "$repfile.new", $repfile or die;
        PAUSE::newfile_hook($repfile);
    } else {
        die "Could not write-open >$repfile:$!";
    }
}

sub rewrite03 {
    my($self) = shift;
    #
    # Rewriting 03modlist.data
    #
    $Logger->log_debug("entering rewrite03");

    my $MLROOT = $self->mlroot;
    my $repfile = "$MLROOT/../../modules/03modlist.data";
    my $list = "";
    my $olist = "";
    local($/) = "\n";
    our $GZIP = $PAUSE::Config->{GZIP_PATH};
    if (-f "$repfile.gz") {
        if (
          open my $fh, "$GZIP --stdout --uncompress $repfile.gz|"
        ) {
          if ($] > 5.007) {
              require Encode;
              binmode $fh, ":utf8";
          }
          while (<$fh>) {
              next if 1../^\s*$/;
              $olist .= $_;
          }
          close $fh;
        } else {
            $Logger->log("couldn't open $repfile $!");
        }
    } else {
        $Logger->log("no 03modlists exist; won't try to read it");
    }
    my $date = HTTP::Date::time2str();

    my $header = sprintf qq{File:        03modlist.data
Description: This was once the "registered module list" but has been retired.
        No replacement is planned.
Modcount:    %d
Written-By:  %s
Date:        %s

}, 0, $PAUSE::Id, $date;

    $list = qq{
    package CPAN::Modulelist;

    sub data {
      return {};
    }

    1;
};

    $list =~ s/^\s+//gm;

    if ($list ne $olist) {
        my $F;
        if (open $F, ">", "$repfile.new") {
            if ($] > 5.007) {
                require Encode;
                binmode $F, ":utf8";
            }
            print $F $header;
            print $F $list;
        } else {
            $Logger->log("couldn't open $repfile.new: $!");
        }
        close $F or die "Couldn't close: $!";
        rename "$repfile.new", $repfile or
            $Logger->log("couldn't rename to $repfile: $!");
        PAUSE::newfile_hook($repfile);
        0==system "$GZIP $PAUSE::Config->{GZIP_OPTIONS} --stdout $repfile > $repfile.gz.new"
            or $Logger->log([ "couldn't gzip $repfile: %s", Process::Status->as_struct ]);
        rename "$repfile.gz.new", "$repfile.gz" or
            $Logger->log("couldn't rename to '$repfile.gz': $!");
        PAUSE::newfile_hook("$repfile.gz");
    }
}

sub rewrite06 {
    my($self) = shift;
    #
    # Rewriting 06perms.txt
    #
    $Logger->log_debug("entering rewrite06");

    my $MLROOT = $self->mlroot;
    my $repfile = "$MLROOT/../../modules/06perms.txt";
    my $list = "";
    my $olist = "";
    local($/) = "\n";
    our $GZIP = $PAUSE::Config->{GZIP_PATH};
    if (-f "$repfile.gz") {
        if (
            open my $fh, "$GZIP --stdout --uncompress $repfile.gz|"
           ) {
            while (<$fh>) {
                next if 1../^\s*$/;
                $olist .= $_;
            }
            close $fh;
        } else {
            $Logger->log("couldn't open $repfile: $!");
        }
    } else {
        $Logger->log("no 06perms.txt.gz exist; won't try to read it");
    }
    my $date = HTTP::Date::time2str();
    my $dbh = $self->connect;
    my @query       = (
        qq{SELECT mods.modid, mods.userid, 'm' FROM mods WHERE mlstatus <> 'delete'},
        qq{SELECT primeur.package, primeur.userid, 'f' FROM primeur},
        qq{SELECT perms.package, perms.userid, 'c' FROM perms},
    );

    my %seen;
    {
        for my $query (@query) {
            my $sth = $dbh->prepare($query);
            $sth->execute();
            while (my @row = $sth->fetchrow_array()) {
                $seen{join ",", @row[0,1]} ||= $row[2];
            }
            $sth->finish;
        }
    }
    my $header = sprintf qq{File:        06perms.txt
Description: CSV file of upload permission to the CPAN per namespace
    best-permission is one of "m" for "modulelist", "f" for
    "first-come", "c" for "co-maint"
Columns:     package,userid,best-permission
Line-Count:  %d
Written-By:  %s
Date:        %s

}, scalar keys %seen, $PAUSE::Id, $date;

    {
        for my $k (sort keys %seen) {
            $list .= sprintf "%s,%s\n", $k, $seen{$k};
        }
    }
    if ($list eq $olist) {
        $Logger->log("06perms.txt has not changed; won't rewrite");
    } else {
        my $F;
        my $gitfile = File::Spec->catfile($self->gitroot, '06perms.txt');
        if (open $F, ">:utf8", $gitfile) {
            print $F $header;
            print $F $list;
        } else {
            $Logger->log("couldn't open $gitfile: $!");
        }
        close $F or die "Couldn't close: $!";
        $self->git->add({}, '06perms.txt');
        $self->_install($gitfile);
        PAUSE::newfile_hook($repfile);
        0==system "$GZIP $PAUSE::Config->{GZIP_OPTIONS} --stdout $repfile > $repfile.gz.new"
            or $Logger->log([ "couldn't gzip $repfile: %s", Process::Status->as_struct ]);
        rename "$repfile.gz.new", "$repfile.gz" or
            $Logger->log("couldn't rename to $repfile.gz: $!");
        PAUSE::newfile_hook("$repfile.gz");
    }
}

sub chdir_ln_chdir {
    my ($self, $postdir, $link_target, $link_name, $log) = @_;
    chdir $postdir or die "Couln't chdir to $postdir";
    my($dir) = File::Basename::dirname($link_name);
    mkpath $dir;
    chdir $dir or die "Couldn't chdir to $dir $!";
    my $pwd = Cwd::cwd();

    unless (-e $link_target){
        require Carp;
        Carp::confess("symlnk target $link_target does not exist in $pwd");
        # return;
    }

    if (-l $link_target) {
        $Logger->log([
          "won't create symlink to symlink: %s",
          { name => $link_name, target => $link_target, pwd => $pwd },
        ]);
        return;
    }

    $link_name = File::Basename::basename($link_name);

    # The from/to names are prexisting, and I didn't dig into how they're used.
    # I think they are *bad* names, because I think of a link going /from/ its
    # name /to/ its target, but for now, I will not throw myself down this
    # rabbit hole. -- rjbs, 2019-04-27
    push @$log, { postdir => $postdir, from => $link_target, to => $link_name };

    if (-l $link_name) {
        my ($foundlink) = readlink $link_name or die "couldn't read link $link_name in $dir";
        if ($foundlink eq $link_target) {
            $Logger->log_debug([
              "symlink already existed: %s",
              { name => $link_name, target => $link_target, dir => $dir },
            ]);
            return;
        }
    }
    if (-l $link_name or -f $link_name) {
        $Logger->log([
          "unlinking about-to-be-replaced entity: %s",
          { name => $link_name, dir => $dir },
        ]);
        unlink $link_name or die qq{couldn't unlink $link_name: $!};
    } elsif (-d $link_name) {
        $Logger->log("ALERT: Have to rmtree $link_name in $dir");
        rmtree $link_name;
    }
    symlink $link_target, $link_name
      or die "couldn't symlink($link_target, $link_name): $!";

    chdir $postdir or die "couldn't chdir to $postdir: $!"
}

sub as_ds {
    my($self,$sth) = @_;
    my $result;
    # If we produce the datastructure as it would seem natural,
    # i.e. each primary key became key in a hash, and each table row
    # would be represented as a hash, we would produce 250k instead of
    # 60. After compression the ratio is still 2:1.
    $result = [];
    while (my @row = $sth->fetchrow_array) {
        if ($] > 5.007) {
            require Encode;
            for (@row) {
                defined && /[^\000-\177]/ && Encode::_utf8_on($_);
            }
        }
        push @$result, \@row;
    }
    $result;
}

sub gitroot {
    $PAUSE::Config->{GITROOT};
}

sub git {
    my $self = shift;
    return $self->{_git_wrapper} ||= Git::Wrapper->new($self->gitroot);
}

sub mlroot {
    my $self = shift;
    return $self->{MLROOT} if defined $self->{MLROOT};
    my $mlroot = $PAUSE::Config->{MLROOT};
    $mlroot =~ s|/+$||; # I found the trailing slash annoying
    $self->{MLROOT} = $mlroot;
}

1;
__END__

=head1 NAME

PAUSE::mldistwatch - The module driving the infamous PAUSE indexer

=head1 SYNOPSIS

 See mldistwatch

=head1 DESCRIPTION

We run through the whole filesystem and check for new files and for
goners. We do this usually from a cronjob once per hour to catch file
events that nobody has dealt with yet.

We compare found files and goners with the database of distribution
files and decide if we have to examine them closer. We also create a
trivial "database" of CHECKSUMS in the same directory as a distro
resides.

We unzip new files into a tree and examine files in that tree
and compare these with data about packages in the database.

During the course we write mails.

When we are done, we create summaries from the database.

The paused daemon immediately triggers I<small> mldistwatch runs.
The purpose of the C<--pick> parameter is to focus on the indexing of
one or more distros. When the C<--pick=distro> parameter is given
(which may be given multiple times), writing of the C<0*> files is
skipped. No find() takes place. Non-existent distros are not removed
from the database.

=head2 Checks done on distributions before entering them in CPAN

The following methods are called on each L<PAUSE::dist> object in order
to check its validity for indexing:

  $dio->ignoredist # must return false
  $dio->examine_dist; # checks for perl, developer, version, etc. and untars
  $dio->skip # must return false
  $dio->read_dist;
  $dio->extract_readme_and_meta;
  $dio->check_blib;
  $dio->check_multiple_root;
  $dio->check_world_writable;
  $dio->examine_pms;

Then the C<_userid_has_permissions_on_package> method is called to
check permissions.

=head1 SEE ALSO

L<PAUSE>

=cut

#Local Variables:
#mode: cperl
#cperl-indent-level: 4
#End:
