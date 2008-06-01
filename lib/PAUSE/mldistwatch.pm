
use version 0.47; # 0.46 had leading whitespace and ".47" problems

use CPAN (); # only for CPAN::Version
use CPAN::Checksums 1.050; # 1.050 introduced atomic writing
use Cwd ();
use DBI;
use Data::Dumper ();
use DirHandle ();
use Dumpvalue ();
use DynaLoader ();
use Exporter ();
use ExtUtils::MakeMaker ();
use ExtUtils::Manifest;
use Fcntl qw();
use File::Basename ();
use File::Copy ();
use File::Temp 0.14 (); # begin of OO interface
use HTTP::Date ();
use JSON ();
use List::Util ();
use Mail::Send ();
use PAUSE ();
use PAUSE::MailAddress ();
use Safe;
use Text::Format;
use YAML ();

$Data::Dumper::Indent = 1;

# "MAIN" at the end of file to guarantee all packages are inintialized

{
    package PAUSE::mldistwatch::Constants;
    # constants used for index_status:
    use constant EDUALOLDER => 50; # pumpkings only
    use constant EDUALYOUNGER => 30; # pumpkings only
    use constant EOPENFILE => 21;
    use constant EMISSPERM => 20;
    use constant EPARSEVERSION => 10;
    use constant EOLDRELEASE => 4;
    use constant EMTIMEFALLING => 3; # deprecated after rev 478
    use constant EVERFALLING => 2;
    use constant OK => 1;
}

{
    package PAUSE::mldistwatch;
    ###### data initialization ######
    use DB_File;
    use Fcntl qw(O_RDWR O_CREAT);
    use File::Find;
    use File::Path qw(rmtree mkpath);
    our $Id = q$Id$;
    $PAUSE::mldistwatch::SUPPORT_BZ2 = 0;
    if ($PAUSE::mldistwatch::SUPPORT_BZ2) {
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
                          (
                          perl-?5[._-](\d{3}(_[0-4][0-9])?|\d*[02468]\.\d+)
                          |
                          ponie-[\d.\-]
                         )
                          (?:
                          \.tar[._-]gz
                          |
                          \.tar\.bz2
                         )
                          \z
                      }x;
    } else {
        our $ISA_REGULAR_PERL = qr{
                          /
                          (
                          perl-?5[._-](\d{3}(_[0-4][0-9])?|\d*[02468]\.\d+)
                          |
                          ponie-[\d.\-]
                         )
                          (?:
                          \.tar[._-]gz
                         )
                          \z
                      }x;
    }
}


package PAUSE::mldistwatch;
use Fcntl qw(:flock);
# this class shows that it was born as spaghetticode

sub new {
    my $class = shift;
    my $opt = shift;

    my $fh;
    unless ($opt->{pick}) { # pick files shall not block full run
        my $pidfile = "/var/run/mldistwatch.pid";
        if (open $fh, "+>>", $pidfile) {
            if (flock $fh, LOCK_EX|LOCK_NB) {
                truncate $fh, 0 or die;
                seek $fh, 0, 0;
                my $ofh = select $fh;
                $|=1;
                print $fh $$, "\n";
                select $ofh;
            } else {
                die "other mlistwatch job running, ".
                    "will not run at the same time";
            }
        } else {
            die "Could not open pidfile[$pidfile]: $!";
        }
    }

    my $tarbin = "/usr/local/bin/tar";
    $tarbin = "/bin/tar" unless -x $tarbin;
    die "No tarbin found" unless -x $tarbin;

    my $unzipbin = "/usr/local/bin/unzip";
    $unzipbin = "/usr/bin/unzip" unless -x $unzipbin;
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
    $self->verbose(1,"Starting");
    $self;
}

sub sleep {
    my($self) = @_;
    my $sleep = $self->{OPT}{sleep} ||= 1;
    sleep $sleep;
}

sub verbose {
    my($self,$level,@what) = @_;
    our $Id;
    unless (@what) {
        @what = ("warning: verbose called without \@what: ", $level);
        $level = 1;
    }
    return if $level > $self->{VERBOSE};
    unless (exists $self->{INTRODUCED}) {
        my $now = scalar localtime;
        require Data::Dumper;
        unshift @what, "Running $0, $Id, $now",
            Data::Dumper->new([$self],[qw()])->Indent(1)->Useqq(1)->Dump;
        $self->{INTRODUCED} = undef;
    }
    my $logfh;
    if (my $logfile = $self->{OPT}{logfile}) {
        open $logfh, ">>", $logfile or die;
        unshift @what, scalar localtime;
        push @what, "\n";
    } else {
        $logfh = *STDOUT;
    }
    print $logfh @what;
}

sub work {
    my $self = shift;
    my $startdir = Cwd::cwd();
    my $MLROOT = $self->mlroot;
    chdir $MLROOT
        or die "Couldn't chdir to $MLROOT";
    $self->init_all();
    $self->verbose(2,"Registering new users\n");
    $self->set_user_active_status();
    my $testdir = File::Temp::tempdir(
                                      "mldistwatch_work_XXXX",
                                      DIR => "/tmp",
                                      CLEANUP => 0,
                                     ) or die "Could not make a tmp directory";
    chdir $testdir
        or die("Couldn't change to $testdir: $!");
    $self->checkfornew($testdir);
    chdir $startdir or die "Could not chdir to '$startdir'";
    rmtree $testdir;
    return if $self->{OPT}{pick};
    $self->work2;
}

sub work2 {
    my $self = shift;
    $self->rewrite02();
    my $MLROOT = $self->mlroot;
    chdir $MLROOT
        or die "Couldn't chdir to $MLROOT: $!";
    $self->rewrite01();
    $self->rewrite03();
    $self->rewrite06();
    $self->verbose(1, sprintf(
                              "\nFinished rewrite03 and everything at %s\n",
                              scalar localtime
                             ));
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

sub set_user_active_status {
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
            $self->verbose(1,"Warning: user not defined for file[$file]\n");
            next;
        }
        next if exists $active->{$user};
        push @new_active_users, $user;
    }
    $self->filter_dups(\@new_active_users);
    $self->debug_mem;
    return unless @new_active_users;
    $self->verbose(2,"Info: new_active_users[@new_active_users]");
    my $sth = $db->prepare("UPDATE users
                            SET ustatus='active', ustatus_ch=NOW()
                             WHERE userid=?");
    for my $user (@new_active_users) {
        $sth->execute($user);
    }
    $sth->finish;
}

sub connect {
    my $self = shift;
    return $self->{DBH} if $self->{DBH};
    my $dbh = DBI->connect(
                           $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
                           $PAUSE::Config->{MOD_DATA_SOURCE_USER},
                           $PAUSE::Config->{MOD_DATA_SOURCE_PW},
                           {
                            RaiseError => 1 }
                          ) or die $DBI::errstr;
    $self->{DBH} = $dbh;
}

sub disconnect {
    my $self = shift;
    return unless $self->{DBH};
    $self->{DBH}->disconnect;
    delete $self->{DBH};
}

sub DESTROY {
    my $self = shift;
    $self->disconnect;
}

sub init_all {
    my $self = shift;
    $self->verbose(2,"Running manifind\n");
    $self->{ALLfound} = $self->manifind;
    $self->verbose(2,"Collecting distmtimes from DB\n");
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
    tie %found, 'DB_File', $fh->filename, O_RDWR|O_CREAT, 0644, $DB_HASH;

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

sub checkfornew {
    my($self,$testdir) = @_;
    local $/ = "";
    my $dbh = $self->connect;
    my $time = time;
    my $alert;
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
        if !$self->{PICK} && $all < 20000;
    $self->verbose(2, "Starting BIGLOOP over $all files\n");
  BIGLOOP: for (my $i=0;scalar @all;$self->empty_dir($testdir)) {
        my $dist = shift @all;
        #
        # Examine all files, even CHECKSUMS and READMEs
        #
        $i++;
        $self->verbose(2,". $dist ..") unless $i%256;

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

        if ($dio->ignoredist){
            delete $self->{ALLlasttime}{$dist};
            delete $self->{ALLfound}{$dist};
            next BIGLOOP;
        }

        if (exists $self->{ALLfound}{$dist}) {
            unless ($dio->mtime_ok($self->{ALLlasttime}{$dist})){
                delete $self->{ALLlasttime}{$dist};
                delete $self->{ALLfound}{$dist};
                next BIGLOOP;
            }
        } else {
            $dio->delete_goner;
            delete $self->{ALLlasttime}{$dist};
            delete $self->{ALLfound}{$dist};
            next BIGLOOP;
        }
        unless ($dio->lock) {
            $self->verbose(1,"Could not obtain a lock on $dist\n");
            next BIGLOOP;
        }
        $self->verbose(1,"\n    Examining $dist ...\n");
        $0 = "mldistwatch: $dist";

        my $userid = PAUSE::dir2user($dist);
        $dio->{USERID} = $userid;

        # >99% of all distros are already registered by the
        # newfilehook but the few coming though mirror(1) are not.
        # Registering *everything* that comes here should catch them
        # and if we re-register this or that it should not hurt.
        my $MLROOT = $self->mlroot;
        PAUSE::newfile_hook("$MLROOT/$dist");

        $dio->examine_dist; # checks for perl, developer, version, etc. and untars
        if ($dio->skip){
            delete $self->{ALLlasttime}{$dist};
            delete $self->{ALLfound}{$dist};
            next BIGLOOP;
        }

        $dio->read_dist;
        $dio->extract_readme_and_yaml;
        if ($dio->{YAML_CONTENT}{distribution_type} =~ m/^(script)$/) {
            next BIGLOOP;
        }
        $dio->check_blib;
        $dio->check_multiple_root;
        $dio->examine_pms;      # will switch user

        $dio->mail_summary;
        $self->sleep;
        $dio->set_indexed;

        $alert .= $dio->alert;  # now $dio can go out of scope
    }
    untie @all;
    undef $fh;
    if ($alert) {
        $self->verbose(1,$alert); # summary
        if ($PAUSE::Config->{TESTHOST}) {
        } else {
            our $Id;
            my($msg) = Mail::Send->new(
                                       To => $PAUSE::Config->{ADMIN},
                                       Subject => "Upload Permission or Version mismatch"
                                      );
            $msg->add("From", "PAUSE <$PAUSE::Config->{UPLOAD}>");
            my $fh  = $msg->open('sendmail');
            print $fh "Not indexed.\n\t$Id\n\n", $alert;
            $fh->close;
        }
    }
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

sub rewrite02 {
    my $self = shift;
    our $Id;
    #
    # Rewriting 02packages.details.txt
    #
    $self->verbose(1,"\n\nEntering rewrite02\n");

    my $dbh = $self->connect;
    my $MLROOT = $self->mlroot;
    my $repfile = "$MLROOT/../../modules/02packages.details.txt";
    my $list = "";
    my $olist = "";
    local($/) = "\n";
    if (
        -f "$repfile.gz" and
        open F, "$PAUSE::Config->{GZIP} --stdout --uncompress $repfile.gz|"
       ) {
        while (<F>) {
            next if 1../^$/;
            $olist .= $_;
        }
        close F;
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
    $self->verbose(2,"numrows[$numrows]\n");
    while (@row = $sth->fetchrow_array) {
        my($one,$two);
        my $infile = $row[0];
        $infile =~ s/^.+:://;
        next unless $row[3];
        next unless index($row[3],"$infile.pm")>=0 or
            $row[3]=~/VERSION/i; # VERSION is Russ Allbery's idea to
                                 # force inclusion
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
    die "Absurd small number of lines" unless $numlines > 1000;
    my $header = qq{File:         02packages.details.txt
URL:          http://www.perl.com/CPAN/modules/02packages.details.txt
Description:  Package names found in directory \$CPAN/authors/id/
Columns:      package name, version, path
Intended-For: Automated fetch routines, namespace documentation.
Written-By:   $Id
Line-Count:   $numlines
Last-Updated: $date\n\n};

    $list .= join "", sort {lc $a cmp lc $b} @listing02;
    if ($list ne $olist) {
        my $F;
        if (open $F, ">", "$repfile.new") {
            print $F $header;
            print $F $list;
        } else {
            $self->verbose(1,"Couldn't open >02packages\n");
        }
        close $F or die "Couldn't close: $!";
        rename "$repfile.new", $repfile or
            $self->verbose("Couldn't rename to '$repfile': $!");
        PAUSE::newfile_hook($repfile);
        0==system "$PAUSE::Config->{GZIP} --best --rsyncable --stdout $repfile > $repfile.gz.new"
            or $self->verbose("Couldn't gzip for some reason");
        rename "$repfile.gz.new", "$repfile.gz" or
            $self->verbose("Couldn't rename to '$repfile.gz': $!");
        PAUSE::newfile_hook("$repfile.gz");
    }
}

sub rewrite01 {
    my($self) = shift;
    #
    # Rewriting 01modules.index.html
    #
    $self->verbose(1, "\nEntering rewrite01\n");
    my $dbh = $self->connect;

    my $MLROOT = $self->mlroot;
    my $repfile = "$MLROOT/../../modules/01modules.index.html";
    my $list = "";
    my $olist = "";
    local $/;
    local *F;
    if (open F, $repfile) {
        while (<F>) {
            $olist .= $_;
        }
        close F;
    } else {
        $self->verbose(1,"Couldn't open $repfile $!\n");
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
    my(@listing01,%count,$count);
    my(%seen);

    my(%usercache,%userdircache,$i);
    while (my($pkg,$pkgdist) = $sth->fetchrow_array) {
        my %pkg = (rootpack => $pkg, dist => $pkgdist);
        $pkg{rootpack} =~ s/:.*//;
        # We don't want to list perl distribution
        next if $pkg{dist} =~ m|/perl-?5|;
        if ($seen{$pkg{dist},$pkg{rootpack}}++) {
            next;
        }
        if ($firstlevel{$pkg{rootpack}}) {
            #print "01 will have: $pkg{rootpack}/$pkg{dist}\n";
        } else {
            next;
        }

        $i++;
        @pkg{qw/size mtime/} =
            (stat "$MLROOT/$pkg{dist}")[7,9];
        next unless defined $pkg{size}; # somebody removed it while we were running
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
        if ($PAUSE::mldistwatch::SUPPORT_BZ2) {
            ($pkg{readme} = $pkg{dist}) =~
                s/\.(tar[._-]gz|tar\.bz2|tar.Z|tgz|zip)$/.readme/;
        } else {
            ($pkg{readme} = $pkg{dist}) =~
                s/\.(tar[._-]gz|tar.Z|tgz|zip)$/.readme/;
        }
        $pkg{readmefn} = File::Basename::basename($pkg{readme});

        $pkg{chapterid} = $achapter{$pkg{rootpack}}
            || $achapter{"$pkg{rootpack}\::"};

        if (defined $pkg{chapterid}) {
            if (defined $chaptitle[$pkg{chapterid}]) {
                $pkg{chapter} = $chaptitle[$pkg{chapterid}]
            } else {
                $pkg{chapter} = "99_Not_In_Modulelist";
                $self->verbose(1,"\nfound no chapterid for $pkg{rootpack}\n");
            }
        } else {
            $pkg{chapter} = "99_Not_In_Modulelist";
            $self->verbose(1,"found no chapter for $pkg{rootpack}\n");
        }


        $self->verbose(2,".") if !($i % 16);
        my $bymod = "$MLROOT/../../modules/".
            "by-module/$pkg{rootpack}/$pkg{filenameonly}";
        my $bycat = "$MLROOT/../../modules/".
            "by-category/$pkg{chapter}/$pkg{rootpack}/$pkg{filenameonly}";
        next if -e $bymod and -e $bycat;

        $self->chdir_ln_chdir($MLROOT,
                              "../../../authors/id/$pkg{dist}",
                              "../../modules/by-module/$pkg{rootpack}".
                              "/$pkg{filenameonly}");
        $self->chdir_ln_chdir($MLROOT,
                              "../../../authors/id/$pkg{readme}",
                              "../../modules/by-module/$pkg{rootpack}".
                              "/$pkg{readmefn}")
            if -f $pkg{readme};
        $self->chdir_ln_chdir($MLROOT,
                              "../../../authors/id/$userdir",
                              "../../modules/by-module/$pkg{rootpack}/$pkg{userid}");
        $self->chdir_ln_chdir($MLROOT,
                              "../../../../authors/id/$pkg{dist}",
                              "../../modules/by-category/$pkg{chapter}".
                              "/$pkg{rootpack}/$pkg{filenameonly}");
        $self->chdir_ln_chdir($MLROOT,
                              "../../../../authors/id/$pkg{readme}",
                              "../../modules/by-category/$pkg{chapter}".
                              "/$pkg{rootpack}/$pkg{readmefn}")
            if -f $pkg{readme};
        $self->chdir_ln_chdir($MLROOT,
                              "../../../../authors/id/$userdir",
                              "../../modules/by-category/$pkg{chapter}".
                              "/$pkg{rootpack}/$pkg{userid}");
    }
    $list = qq{<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"><html><head><title>Modules
on CPAN alphabetically</title></head><body>
<h1>CPAN\'s $count modules distributions</h1>
<h3>in alphabetical order by modules contained in the distributions</h3>
<i>} .
    scalar gmtime() .
        qq{ GMT</i>

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
        if (open F, ">$repfile") {
            print F $list;
            close F;
            $self->write_01sorted(\@listing01);
        } else {
            $self->verbose(1,"Couldn't open 01modules...\n");
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

  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;

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
               sort {$b->[10] <=> lc $a->[10] # mtime
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
        if ($PAUSE::mldistwatch::SUPPORT_BZ2) {
            ($package{basename}) =
                $package{filenameonly} =~ /^(.*)\.(?:tar[._-]gz|tar\.bz2|tar.Z|tgz|zip)$/;
        } else {
            ($package{basename}) =
                $package{filenameonly} =~ /^(.*)\.(?:tar[._-]gz|tar.Z|tgz|zip)$/;
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
    # $self->verbose(1,"Writing $rssfile\n");
    if (open my $F, ">", "$rssfile.new") {
        print $F $rss;
        close $F;
        rename "$rssfile.new", $rssfile or die;
        PAUSE::newfile_hook($rssfile);
    } else {
        die "Could not write-open >$rssfile:$!";
    }

    my $repfile = "$MLROOT/../../modules/01modules.mtime.html";
    # $self->verbose(1,"Writing $repfile\n");
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
    our $Id;
    #
    # Rewriting 03modlist.data
    #
    $self->verbose(1,"\nEntering rewrite03\n");

    my $MLROOT = $self->mlroot;
    my $repfile = "$MLROOT/../../modules/03modlist.data";
    my $list = "";
    my $olist = "";
    local($/) = "\n";
    if (
        -f "$repfile.gz" and
        open F, "$PAUSE::Config->{GZIP} --stdout --uncompress $repfile.gz|"
       ) {
        if ($] > 5.007) {
            require Encode;
            binmode F, ":utf8";
        }
        while (<F>) {
            next if 1../^\s*$/;
            $olist .= $_;
        }
        close F;
    } else {
        $self->verbose(1,"Couldn't open $repfile $!\n");
    }
    my $date = HTTP::Date::time2str();
    my $dbh = $self->connect;
    my $sth = $dbh->prepare(qq{SELECT modid, statd, stats, statl,
                                    stati, statp, description, userid, chapterid
                             FROM mods WHERE mlstatus = "list"});
    $sth->execute;
    my $header = sprintf qq{File:        03modlist.data
Description: These are the data that are published in the module
        list, but they may be more recent than the latest posted
        modulelist. Over time we\'ll make sure that these data
        can be used to print the whole part two of the
        modulelist. Currently this is not the case.
Modcount:    %d
Written-By:  %s
Date:        %s

}, $sth->rows, $Id, $date;

    $list = qq{
    package CPAN::Modulelist;
    # Usage: print Data::Dumper->new([CPAN::Modulelist->data])->Dump or similar
    # cannot 'use strict', because we normally run under Safe
    # use strict;

    sub data {
      my \$result = {};
      my \$primary = "modid";
      for (\@\$CPAN::Modulelist::data){
        my %hash;
        \@hash{\@\$CPAN::Modulelist::cols} = \@\$_;
        \$result->{\$hash{\$primary}} = \\%hash;
      }
      \$result;

    }
  };


    $list .= Data::Dumper->new([
                                $sth->{NAME},
                                $self->as_ds($sth)
                               ],
                               ["CPAN::Modulelist::cols",
                                "CPAN::Modulelist::data"]
                              )->Dump;

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
            $self->verbose(1,"Couldn't open >03...\n");
        }
        close $F or die "Couldn't close: $!";
        rename "$repfile.new", $repfile or
            $self->verbose("Couldn't rename to '$repfile': $!");
        PAUSE::newfile_hook($repfile);
        0==system "$PAUSE::Config->{GZIP} --best --rsyncable --stdout $repfile > $repfile.gz.new"
            or $self->verbose("Couldn't gzip for some reason");
        rename "$repfile.gz.new", "$repfile.gz" or
            $self->verbose("Couldn't rename to '$repfile.gz': $!");
        PAUSE::newfile_hook("$repfile.gz");
    }
}

sub rewrite06 {
    my($self) = shift;
    our $Id;
    #
    # Rewriting 06perms.txt
    #
    $self->verbose(1,"\nEntering rewrite06\n");

    my $MLROOT = $self->mlroot;
    my $repfile = "$MLROOT/../../modules/06perms.txt";
    my $list = "";
    my $olist = "";
    local($/) = "\n";
    if (
        -f "$repfile.gz" and
        open F, "$PAUSE::Config->{GZIP} --stdout --uncompress $repfile.gz|"
       ) {
        while (<F>) {
            next if 1../^\s*$/;
            $olist .= $_;
        }
        close F;
    } else {
        $self->verbose(1,"Couldn't open $repfile $!\n");
    }
    my $date = HTTP::Date::time2str();
    my $dbh = $self->connect;
    my @query       = (
                qq{SELECT mods.modid,
                          mods.userid,
                          "m"
                     FROM mods
},
                qq{SELECT primeur.package,
                          primeur.userid,
                          "f"
                     FROM primeur
},
                qq{SELECT perms.package,
                          perms.userid,
                          "c"
                     FROM perms
},
               );

    my %seen;
    {
        for my $query (@query) {
            my $sth = $dbh->prepare($query);
            $sth->execute();
            if ($sth->rows > 0) {
                while (my @row = $sth->fetchrow_array()) {
                    $seen{join ",", @row[0,1]} ||= $row[2];
                }
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

}, scalar keys %seen, $Id, $date;

    {
        for my $k (sort keys %seen) {
            $list .= sprintf "%s,%s\n", $k, $seen{$k};
        }
    }
    if ($list ne $olist) {
        my $F;
        if (open $F, ">:utf8", "$repfile.new") {
            print $F $header;
            print $F $list;
        } else {
            $self->verbose(1,"Couldn't open >06...\n");
        }
        close $F or die "Couldn't close: $!";
        rename "$repfile.new", $repfile or
            $self->verbose("Couldn't rename to '$repfile': $!");
        PAUSE::newfile_hook($repfile);
        0==system "$PAUSE::Config->{GZIP} --best --rsyncable --stdout $repfile > $repfile.gz.new"
            or $self->verbose("Couldn't gzip for some reason");
        rename "$repfile.gz.new", "$repfile.gz" or
            $self->verbose("Couldn't rename to '$repfile.gz': $!");
        PAUSE::newfile_hook("$repfile.gz");
    }
}

sub chdir_ln_chdir {
    my($self,$postdir,$from,$to) = @_;
    chdir $postdir or die "Couln't chdir to $postdir";
    my($dir) = File::Basename::dirname($to);
    mkpath $dir;
    chdir $dir or die "Couldn't chdir to $dir $!";
    my $pwd = Cwd::cwd();
    unless (-e $from){
        require Carp;
        Carp::confess("not exists: from[$from]dir[$dir]pwd[$pwd]");
        # return;
    }
    if (-l $from) {
        $self->verbose(1,"Won't create symlink[$to] to symlink[$from] in pwd[$pwd]\n");
        return;
    }
    $to = File::Basename::basename($to);
    if (-l $to) {
        my($foundlink) = readlink $to or die "Couldn't read link $to in $dir";
        if ($foundlink eq $from) {
            # $self->verbose(2,"Keeping old symlink $from in dir $dir file $to\n");
            return;
        }
    }
    if (-l $to) {
        $self->verbose(1, qq{unlinking symlink $to in $dir\n});
        unlink $to or die qq{Couldn\'t unlink $to $!};
    } elsif (-f $to) {
        $self->verbose(1, "unlinking file $to in dir $dir\n");
        unlink $to or die qq{Couldn\'t unlink $to $!};
    } elsif (-d $to) {
        $self->verbose(1,"ALERT: Have to rmtree $to in dir $dir\n");
        rmtree $to;
    }
    symlink $from, $to or die "Couldn't symlink $from, $to $!";
    chdir $postdir or die "Couldn't chdir to $postdir $!"
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

sub mlroot {
    my $self = shift;
    return $self->{MLROOT} if defined $self->{MLROOT};
    my $mlroot = $PAUSE::Config->{MLROOT};
    $mlroot =~ s|/+$||; # I found the trailing slash annoying
    $self->{MLROOT} = $mlroot;
}

#####################################################################
######################### start of packages #########################
#####################################################################


{
    package PAUSE::dist;
    use vars qw(%CHECKSUMDONE $AUTOLOAD);

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
        my($self, $dir) = @_;
        return if $CHECKSUMDONE{$dir}++;
        local($CPAN::Checksums::CAUTION) = 1;
        local($CPAN::Checksums::SIGNING_PROGRAM) =
            $PAUSE::Config->{CHECKSUMS_SIGNING_PROGRAM};
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
                $dbh->do(qq{UPDATE distmtimes
                     SET distmtime='$mtime', distmdatetime=from_unixtime('$mtime')
                   WHERE dist='$dist'});
                $self->verbose(1,"DEBUG5: mtime assigned [$mtime] to dist[$dist]\n");
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
        if ($PAUSE::mldistwatch::SUPPORT_BZ2) {
            if ($dist =~ /\.tar\.bz2$/) {
                $tar_opt = "tjf";
            }
        }
        open TARTEST, "$tarbin $tar_opt $MLROOT/$dist |";
        while (<TARTEST>) {
            if (m:^\.\./: || m:/\.\./: ) {
                $self->verbose(1,"\n\n    ALERT: Updir detected in $dist!\n\n");
                $self->alert("ALERT: Updir detected in $dist!");
                $self->{COULD_NOT_UNTAR}++;
                return;
            }
        }
        unless (close TARTEST) {
            $self->verbose(1,"\nCould not untar $dist!\n");
            $self->alert("\nCould not untar $dist!\n");
            $self->{COULD_NOT_UNTAR}++;
            return;
        }
        $tar_opt = "xzf";
        if ($PAUSE::mldistwatch::SUPPORT_BZ2) {
            if ($dist =~ /\.tar\.bz2$/) {
                $tar_opt = "xjf";
            }
        }
        $self->verbose(1,"Going to untar. Running '$tarbin' '$tar_opt' '$MLROOT/$dist'\n");
        unless (system($tarbin,$tar_opt,"$MLROOT/$dist")==0) {
            $self->verbose(1, "Some error occurred during unzipping. Let's retry with -v:\n");
            unless (system("$tarbin v$tar_opt $MLROOT/$dist")==0) {
                $self->verbose(1, "Some error occurred during unzipping again; giving up\n");
            }
        }
        $self->verbose(1,"untarred '$MLROOT/$dist'\n");
        return 1;
    }

    # package PAUSE::dist;
    sub skip { shift->{SKIP} }

    # package PAUSE::dist;
    sub examine_dist {
        my($self) = @_;
        my $dist = $self->{DIST};
        my $MLROOT = $self->mlroot;
        my($suffix,$skip);
        $suffix = $skip = "";
        my $suffqr = qr/\.(tgz|tar[\._-]gz|tar\.Z)$/;
        if ($PAUSE::mldistwatch::SUPPORT_BZ2) {
            $suffqr = qr/\.(tgz|tar[\._-]gz|tar\.bz2|tar\.Z)$/;
        }
        if ($dist =~ /$PAUSE::mldistwatch::ISA_REGULAR_PERL/) {
            my($u) = PAUSE::dir2user($dist); # =~ /([A-Z][^\/]+)/; # XXX dist2user
            $self->verbose(1,"perl dist $dist from $u. Is he a trusted guy?\n");
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
                $self->verbose(1,"Yes.\n");
            } else {
                $skip = 1;
                $self->verbose(1,"NO! Skip set to [$skip]\n");
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
               ) {
                $self->verbose(1,"  developer release\n");
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
                    $self->verbose(1,"    no gunzip on $file\n");
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
                $self->verbose(1,"  no dist\n");
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
Please contact modules\@perl.org if there are any open questions.
  $PAUSE::mldistwatch::Id\n";
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
        my $show_meta_yml = 1;
        if ($show_meta_yml) {
            push @m, qq{
               User: $author ($asciiname)
  Distribution file: $distrobasename
    Number of files: $nfiles
         *.pm files: $pmfiles
             README: $self->{README}
           META.yml: $self->{YAML}
  Timestamp of file: $mtime UTC
   Time of this run: $time UTC\n\n};
        } else {
            push @m, qq{
               User: $author ($asciiname)
  Distribution file: $distrobasename
    Number of files: $nfiles
         *.pm files: $pmfiles
             README: $self->{README}
  Timestamp of file: $mtime UTC
   Time of this run: $time UTC\n\n};
        }
        my $tf = Text::Format->new(firstIndent=>0);

        my $status_over_all;

        if (0) {
        } elsif ($self->{HAS_MULTIPLE_ROOT}) {

            push @m, $tf->format(qq{The distribution does not unpack
                into a single directory and is therefore not being
                indexed. Hint: try 'make dist'. (The directory entries
                found were: @{$self->{HAS_MULTIPLE_ROOT}})});

            push @m, qq{\n\n};

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
                    if ($self->version_from_yaml_ok) {

                        push @m, qq{Nothing in this distro has been
                     indexed, because according to META.yml this
                     package does not provide any modules.\n\n};
                        $status_over_all = "Empty_provides";

                    } else {

                        push @m, qq{No package statements could be
                     found in the distro (maybe a script or
                     documentation distribution?)\n\n};
                        $status_over_all = "Empty_no_pm";

                    }
                } else {
                    # no need to write a report at all
                    return;
                }

            }
        }
        push @m, qq{__END__\n};
        my $pma = PAUSE::MailAddress->new_from_userid($author,{dbh => $self->connect});
        if ($PAUSE::Config->{TESTHOST}) {
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
            my($msg) = Mail::Send
                ->new(
                      To      => $to,
                      Subject => $failed."PAUSE indexer report $substrdistro",
                     );
            $msg->add("From", "PAUSE <$PAUSE::Config->{UPLOAD}>");
            my $fh  = $msg->open('sendmail');
            print $fh @m;
            $fh->close;
            $self->verbose(1,"-->> Sent \"indexer report\" mail about $substrdistro\n");
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
    sub filter_pms {
        my($self) = @_;
        my @pmfile;

        # very similar code is in PAUSE::package::filter_ppps
      MANI: for my $mf ( @{$self->{MANIFOUND}} ) {
            next unless $mf =~ /\.pm$/i;
            my($inmf) = $mf =~ m!^[^/]+/(.+)!; # go one directory down
            next if $inmf =~ m!^(?:t|inc)/!;
            if ($self->{YAML_CONTENT}){
                my $no_index = $self->{YAML_CONTENT}{no_index}
                               || $self->{YAML_CONTENT}{private}; # backward compat
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
                                    $self->verbose(1,"skipping inmf[$inmf] due to ve[$ve]");
                                    next MANI;
                                } else {
                                    $self->verbose(1,"NOT skipping inmf[$inmf] due to ve[$ve]");
                                }
                            }
                        } else {
                            $v =~ s|/+$||;
                            if ($inmf =~ /^$v$rest/){
                                $self->verbose(1,"skipping inmf[$inmf] due to v[$v]");
                                next MANI;
                            } else {
                                $self->verbose(1,"NOT skipping inmf[$inmf] due to v[$v]");
                            }
                        }
                    }
                } else {
                    # noisy:
                    # $self->verbose(1,"no keyword 'no_index' or 'private' in YAML_CONTENT");
                }
            } else {
                # $self->verbose(1,"no YAML_CONTENT"); # too noisy
            }
            push @pmfile, $mf;
        }
        $self->verbose(1,"pmfile[@pmfile]");
        \@pmfile;
    }

    # package PAUSE::dist;
    sub examine_pms {
        my $self = shift;
        return if $self->{HAS_BLIB};
        return if $self->{HAS_MULTIPLE_ROOT};
        return if $self->{COULD_NOT_UNTAR}; # XXX not yet reached, we
                                            # need to re-examine what
                                            # happens without SKIP.
                                            # Currently SKIP shadows
                                            # the event of
                                            # could_not_untar
        my $dist = $self->{DIST};

        my $binary_dist;
        $binary_dist = 1 if $dist =~ /-bin-/i;

        my $pmfiles = $self->filter_pms;
        if (0) {
        } elsif (@$pmfiles) { # examine files
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
                                             YAML_CONTENT => $self->{YAML_CONTENT},
                                            );
                $fio->examine_fio;
            }
        } elsif ($self->version_from_yaml_ok) { # no pmfiles but at least a yaml
            my $yaml = $self->{YAML_CONTENT};
            my $provides = $yaml->{provides};
            if ($provides && %$provides) {
                while (my($k,$v) = each %$provides) {
                    $v->{infile} = "$v->{file} (according to META)";
                    my $pio = PAUSE::package
                        ->new(
                              PACKAGE => $k,
                              DIST => $dist,
                              DIO => $self,
                              PP => $v,
                              TIME => $self->{TIME},
                              PMFILE => "nil",
                              USERID => $self->{USERID},
                              YAML_CONTENT => $self->{YAML_CONTENT},
                             );
                    $pio->examine_pkg;
                }
            }
        } else {
        }
    }

    # package PAUSE::dist
    sub chown_unsafe {
        my($self) = @_;
        return if $self->{CHOWN_UNSAFE_DONE};
        use File::Find;
        my(undef,undef,$uid,$gid) = getpwnam("UNSAFE");
        die "user UNSAFE not found, cannot continue" unless defined $uid;
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
        my $yaml = List::Util::reduce { length $a < length $b ? $a : $b }
            grep !m|/t/|, grep m|/META\.yml$|, @manifind;
        if (defined $yaml) {
            if (-s $yaml) {
                $self->{YAML} = $yaml;
                File::Copy::copy $yaml, "$MLROOT/$sans.meta";
                utime((stat $yaml)[8,9], "$MLROOT/$sans.meta");
                PAUSE::newfile_hook("$MLROOT/$sans.meta");
                eval { $self->{YAML_CONTENT} = YAML::LoadFile($yaml); };
                if ($@) {
                    $self->verbose(1,"Error while parsing YAML: $@");
                    if ($@ =~ /msg: Unrecognized implicit value/) {
                        # let's retry, but let's not expect that this
                        # will work. MakeMaker 6.16 had a bug that
                        # could be fixed like this, at least for
                        # Pod::Simple

                        my $cat = do { open my($f), $yaml or die; local $/; <$f> };
                        $cat =~ s/:(\s+)(\S+)$/:$1"$2"/mg;
                        eval { $self->{YAML_CONTENT} = YAML::Load $cat; };
                        if ($@) {
                            $self->{YAML_CONTENT} = {};
                            $self->{YAML} = "META.yml found but error ".
                                "encountered while loading: $@";
                        }

                    } else {
                        $self->{YAML_CONTENT} = {};
                        $self->{YAML} = "META.yml found but error ".
                            "encountered while loading: $@";
                    }
                }
            } else {
                $self->{YAML} = "Empty META.yml found, ignoring\n";
            }
        } else {
            $self->{YAML} = "No META.yml found\n";
            $self->verbose(1,"No META.yml in $dist");
        }
    }

    # package PAUSE::dist
    sub version_from_yaml_ok {
        my($self) = @_;
        return $self->{VERSION_FROM_YAML_OK} if exists $self->{VERSION_FROM_YAML_OK};
        my $ok = 0;
        my $c = $self->{YAML_CONTENT};
        if (exists $c->{provides}) {
            if (exists $c->{generated_by}) {
                if (my($v) = $c->{generated_by} =~ /Module::Build version ([\d\.]+)/) {
                    if ($v eq "0.250.0") {
                        $ok++;
                    } elsif ($v >= 0.19) {
                        if ($v < 0.26) {
                            # RSAVAGE/Javascript-SHA1-1.01.tgz had an
                            # empty provides hash. Ron did not find
                            # the reason why this happened, but let's
                            # not go overboard, 0.26 seems a good
                            # threshold from the statistics: there
                            # are not many empty provides hashes from
                            # 0.26 up.
                            if (keys %{$c->{provides}}) {
                                $ok++;
                            } else {
                                $ok = 0;
                            }
                        } else {
                            $ok++;
                        }
                    } else {
                        $ok = 0;
                    }
                } else {
                    $ok++;
                }
            } else {
                $ok++;
            }
        }
        return $self->{VERSION_FROM_YAML_OK} = $ok;
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
            $self->verbose(1,"forcing indexing without a lock");
            return 1;
        }
        my $dist = $self->{DIST};
        my $dbh = $self->connect;
        my $rows_affected = $dbh->do("UPDATE distmtimes
                                 SET indexing_at=NOW()
                                 WHERE dist='$dist'
                                 AND indexing_at IS NULL");
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
        my $rows_affected = $dbh->do("UPDATE distmtimes
                                 SET indexed_at=NOW()
                                 WHERE dist='$dist'");
        $rows_affected > 0;
    }
}

{
    package PAUSE::mldistwatch::Constants;
    our $heading =
        {
         EMISSPERM() => "Permission missing",
         EDUALOLDER() => "An older dual-life module stays reference",
         EDUALYOUNGER() => "Dual-life module stays reference",
         EVERFALLING() => "Decreasing version number",
         EMTIMEFALLING() => "Decreasing mtime on a file (category to be deprecated)",
         EOLDRELEASE() => "Release seems outdated",
         EPARSEVERSION() => "Version parsing problem",
         EOPENFILE() => "Problem while reading the distribtion",
         OK() => "Successfully indexed",
        };

    sub heading ($) {
        my($status) = shift;
        # warn "status[$status]";
        $heading->{$status};
    }
}

{
    package PAUSE::pmfile;
    use vars qw($AUTOLOAD);

    sub DESTROY {}

    sub verbose {
        my($self,$level,@what) = @_;
        my $main = $self->{DIO};
        $main->verbose($level,@what);
    }

    # package PAUSE::pmfile;
    sub new {
        my($me) = shift;
        bless { @_ }, ref($me) || $me;
    }

    # package PAUSE::pmfile;
    sub simile {
        my($self,$file,$package) = @_;
        # MakeMaker gives them the chance to have the file Simple.pm in
        # this directory but have the package HTML::Simple in it.
        # Afaik, they wouldn't be able to do so with deeper nested packages
        $file =~ s|.*/||;
        $file =~ s|\.pm||;
        my $ret = $package =~ m/\b\Q$file\E$/;
        $ret ||= 0;
        unless ($ret) {
            # Apache::mod_perl_guide stuffs it into Version.pm
            $ret = 1 if lc $file eq 'version';
        }
        $self->verbose(1,"simile: file[$file] package[$package] ret[$ret]\n");
        $ret;
    }

    # package PAUSE::pmfile;
    sub alert {
        my $self = shift;
        my $what = shift;
        my $dio = $self->{DIO};
        $dio->alert($what);
    }

    sub connect {
        my($self) = @_;
        my $dio = $self->{DIO};
        $dio->connect;
    }

    sub disconnect {
        my($self) = @_;
        my $dio = $self->{DIO};
        $dio->disconnect;
    }

    sub mlroot {
        my($self) = @_;
        my $dio = $self->{DIO};
        $dio->mlroot;
    }

    # package PAUSE::pmfile;
    sub filter_ppps {
        my($self,@ppps) = @_;
        my @res;

        # very similar code is in PAUSE::dist::filter_pms
      MANI: for my $ppp ( @ppps ) {
            if ($self->{YAML_CONTENT}){
                my $no_index = $self->{YAML_CONTENT}{no_index}
                               || $self->{YAML_CONTENT}{private}; # backward compat
                if (ref($no_index) eq 'HASH') {
                    my %map = (
                               package => qr{\z},
                               namespace => qr{::},
                              );
                    for my $k (qw(package namespace)) {
                        next unless my $v = $no_index->{$k};
                        my $rest = $map{$k};
                        if (ref $v eq "ARRAY") {
                            for my $ve (@$v) {
                                $ve =~ s|::$||;
                                if ($ppp =~ /^$ve$rest/){
                                    $self->verbose(1,"skipping ppp[$ppp] due to ve[$ve]");
                                    next MANI;
                                } else {
                                    $self->verbose(1,"NOT skipping ppp[$ppp] due to ve[$ve]");
                                }
                            }
                        } else {
                            $v =~ s|::$||;
                            if ($ppp =~ /^$v$rest/){
                                $self->verbose(1,"skipping ppp[$ppp] due to v[$v]");
                                next MANI;
                            } else {
                                $self->verbose(1,"NOT skipping ppp[$ppp] due to v[$v]");
                            }
                        }
                    }
                } else {
                    $self->verbose(1,"no keyword 'no_index' or 'private' in YAML_CONTENT");
                }
            } else {
                # $self->verbose(1,"no YAML_CONTENT"); # too noisy
            }
            push @res, $ppp;
        }
        $self->verbose(1,"res[@res]");
        @res;
    }

    # package PAUSE::pmfile;
    sub examine_fio {
        # fio: file object
        my $self = shift;
        my $dist = $self->{DIO}{DIST};
        my $dbh = $self->connect;
        my $pmfile = $self->{PMFILE};

        my($filemtime) = (stat $pmfile)[9];
        $self->{MTIME} = $filemtime;

        unless ($self->version_from_yaml_ok) {
            $self->{VERSION} = $self->parse_version;
            if ($self->{VERSION} =~ /^\{.*\}$/) {
                # JSON error message
            } elsif ($self->{VERSION} =~ /[_\s]/){   # ignore developer releases and "You suck!"
                delete $self->{DIO};    # circular reference
                return;
            }
        }

        my($ppp) = $self->packages_per_pmfile;
        my @keys_ppp = $self->filter_ppps(sort keys %$ppp);
        $self->verbose(1,"will check keys_ppp[@keys_ppp]\n");

        #
        # Immediately after each package (pmfile) examined contact
        # the database
        #

        my ($package);
      DBPACK: foreach $package (@keys_ppp) {

            # What do we need? dio, fio, pmfile, time, dist, dbh, alert?
            my $pio = PAUSE::package
                ->new(
                      PACKAGE => $package,
                      DIST => $dist,
                      PP => $ppp->{$package}, # hash containing
                                              # version
                      TIME => $self->{TIME},
                      PMFILE => $pmfile,
                      FIO => $self,
                      USERID => $self->{USERID},
                      YAML_CONTENT => $self->{YAML_CONTENT},
                     );

            $pio->examine_pkg;

        }                       # end foreach package

        delete $self->{DIO};    # circular reference

    }

    # package PAUSE::pmfile
    sub version_from_yaml_ok {
        my($self) = @_;
        return $self->{VERSION_FROM_YAML_OK} if exists $self->{VERSION_FROM_YAML_OK};
        $self->{VERSION_FROM_YAML_OK} = $self->{DIO}->version_from_yaml_ok;
    }

    # package PAUSE::pmfile;
    sub packages_per_pmfile {
        my $self = shift;

        my $ppp = {};
        my $pmfile = $self->{PMFILE};
        my $filemtime = $self->{MTIME};
        my $version = $self->{VERSION};

        open my $fh, "<", "$pmfile" or return $ppp;

        local $/ = "\n";
        my $inpod = 0;

      PLINE: while (<$fh>) {
            chomp;
            my($pline) = $_;
            $inpod = $pline =~ /^=(?!cut)/ ? 1 :
                $pline =~ /^=cut/ ? 0 : $inpod;
            next if $inpod;
            next if substr($pline,0,4) eq "=cut";

            $pline =~ s/\#.*//;
            next if $pline =~ /^\s*$/;
            last PLINE if $pline =~ /\b__(END|DATA)__\b/;

            my $pkg;

            if (
                $pline =~ m{
                         (.*)
                         \bpackage\s+
                         ([\w\:\']+)
                         \s*
                         ( $ | [\}\;] )
                        }x) {
                $pkg = $2;

            }

            if ($pkg) {
                # Found something

                # from package
                $pkg =~ s/\'/::/;
                next PLINE unless $pkg =~ /^[A-Za-z]/;
                next PLINE unless $pkg =~ /\w$/;
                next PLINE if $pkg eq "main";
                # Perl::Critic::Policy::TestingAndDebugging::ProhibitShebangWarningsArg
                # database for modid in mods, package in packages, package in perms
                # alter table mods modify modid varchar(128) binary NOT NULL default '';
                # alter table packages modify package varchar(128) binary NOT NULL default '';
                next PLINE if length($pkg) > 128;
                #restriction
                $ppp->{$pkg}{parsed}++;
                $ppp->{$pkg}{infile} = $pmfile;
                if ($self->simile($pmfile,$pkg)) {
                    $ppp->{$pkg}{simile} = $pmfile;
                    if ($self->version_from_yaml_ok) {
                        my $provides = $self->{DIO}{YAML_CONTENT}{provides};
                        if (exists $provides->{$pkg}) {
                            if (exists $provides->{$pkg}{version}) {
                                my $v = $provides->{$pkg}{version};
                                if ($v =~ /[_\s]/){   # ignore developer releases and "You suck!"
                                    next PLINE;
                                } else {
                                    $ppp->{$pkg}{version} = $self->normalize_version($v);
                                }
                            } else {
                                $ppp->{$pkg}{version} = "undef";
                            }
                        }
                    } else {
                        $ppp->{$pkg}{version} ||= "";
                        $ppp->{$pkg}{version} ||= $version;
                        local($^W)=0;
                        $ppp->{$pkg}{version} =
                            $version
                                if $version
                                    > $ppp->{$pkg}{version} ||
                                        $version
                                            gt $ppp->{$pkg}{version};
                    }
                } else {        # not simile
                    #### it comes later, it would be nonsense
                    #### to set to "undef". MM_Unix gives us
                    #### the best we can reasonably consider
                    $ppp->{$pkg}{version} =
                        $version
                            unless defined $ppp->{$pkg}{version} &&
                                length($ppp->{$pkg}{version});
                }
                $ppp->{$pkg}{filemtime} = $filemtime;
                $ppp->{$pkg}{pause_reg} = time;
            } else {
                # $self->verbose(2,"no pkg found");
            }
        }

        $fh->close;
        $ppp;
    }

    # package PAUSE::pmfile;
    {
        no strict;
        sub parse_version_safely {
            my($parsefile) = @_;
            my $result;
            local *FH;
            local $/ = "\n";
            open(FH,$parsefile) or die "Could not open '$parsefile': $!";
            my $inpod = 0;
            while (<FH>) {
                $inpod = /^=(?!cut)/ ? 1 : /^=cut/ ? 0 : $inpod;
                next if $inpod || /^\s*#/;
                chop;
                # next unless /\$(([\w\:\']*)\bVERSION)\b.*\=/;
                next unless /([\$*])(([\w\:\']*)\bVERSION)\b.*\=/;
                my $current_parsed_line = $_;
                my $eval = qq{
              package ExtUtils::MakeMaker::_version;

              local $1$2;
              \$$2=undef; do {
                  $_
              }; \$$2
          };
                local $^W = 0;
                $result = eval($eval);
                # warn "current_parsed_line[$current_parsed_line]\$\@[$@]";
                if ($@){
                    die +{
                          eval => $eval,
                          line => $current_parsed_line,
                          file => $parsefile,
                          err => $@,
                         } if $@;
                }
                last;
            } #;
            close FH;

            $result = "undef" unless defined $result;
            return $result;
        }
    }

    sub _module_version {
        my $leaf = shift;
        (my $pkg = $leaf) =~ s/\.pm//;
        my ($module, $version, $in_pkg, %version);

        local *FH;
        local $_;
        open(FH,$leaf) or return;
        my $inpod;

        while(<FH>) {
            $inpod = $1 ne 'cut' if /^=(\w+)/;
            next if $inpod or /^\s*#/;

            if(/^\s*package\s+(([\w]+(?:'|::))*([\w]+))/) {
                $module ||= $1 if $3 eq $pkg;
                $in_pkg = $1;
            }
            elsif (my($for_pkg, $rhs) = /[\$*]([\w\:\']*)\bVERSION\b.*\=(.*)/) {
                $for_pkg ||= $in_pkg or next;
                $for_pkg =~ s/::$//;
                $version{$for_pkg} = $rhs;
            }

            if ($module and $version{$module}) {
                require Safe;
                require version;
                local $^W = 0;
                my $s = Safe->new;
                $s->share_from('main', ['*version::']);
                $s->share_from('version', ['&qv']);
                $s->reval('$VERSION = ' . $version{$module});
                $version = $s->reval('$VERSION');

                # Handle version objects
                ($version = $version->normal) =~ s/^v// if ref($version) eq
                    'version';
                if ($version{$module} =~ /\bv?(\d+([_.]\d+){2,})/) {
                    my $v = $1;
                    my $q = pack "U*", ($v =~ /\d+/g);
                    $version = $v if $version eq $q;
                }
                last;
            }
        }
        close(FH);
        return $module ? ($module, $version) : ();
    }

    # package PAUSE::pmfile;
    sub parse_version {
        my $self = shift;

        use strict;

        my $pmfile = $self->{PMFILE};

        my $pmcp = $pmfile;
        for ($pmcp) {
            s/([^\\](\\\\)*)@/$1\\@/g; # thanks to Raphael Manfredi for the
            # solution to escape @s and \
        }
        my($v);
        $self->disconnect; # no guarantee that the connection survives the fork!

        {

            package main; # seems necessary

            my($pid,$kid);
            die "Can't fork: $!" unless defined($pid = open($kid, "-|"));
            if ($pid) {         # parent
                $v = <$kid>;
                # warn ">>>>>>>>read v[$v]<<<<<<<<";
                close $kid;
            } else {
                my($gnam,$gpw,$gid,$gmem) = getgrnam("UNSAFE");
                die "Could not determine GID of UNSAFE" unless $gid;
                my($uname,$upw,$uid,$ugid,$q,$c,$gcos,$udir,$ushell) =
                    getpwnam("UNSAFE");
                die "Could not determine UID of UNSAFE" unless $uid;
                $( = $gid; $) = "$gid $gid";
                $< = $> = $uid;

                # XXX Limit Resources too

                my($comp) = Safe->new("_pause::mldistwatch");
                my $eval = qq{
                  local(\$^W) = 0;
                  PAUSE::pmfile::parse_version_safely("$pmcp");
                 };
                $comp->permit("entereval"); # for MBARBON/Module-Info-0.30.tar.gz
                $comp->share("*PAUSE::pmfile::parse_version_safely");
                $comp->share("*version::new");
                $comp->share("*version::numify");
                $comp->share_from('main', ['*version::',
                                           '*Exporter::',
                                           '*DynaLoader::']);
                $comp->share_from('version', ['&qv']);
                # $comp->permit("require"); # no strict!
                {
                    no strict;
                    local $PAUSE::Config;
                    $v = $comp->reval($eval);
                }
                if ($@){ # still in the child process, out of Safe::reval
                    my $err = $@;
                    # warn ">>>>>>>err[$err]<<<<<<<<";
                    if (ref $err) {
                        if ($err->{line} =~ /[\$*]([\w\:\']*)\bVERSION\b.*\=(.*)/) {
                            $v = $comp->reval($2);
                        }
                        if ($@) {
                            warn sprintf("reval failed: err[%s] for eval[%s]",
                                         JSON::objToJson($err,{pretty => 1}),
                                         $eval,
                                        );
                            $v = JSON::objToJson($err);
                        }
                    } else {
                        $v = JSON::objToJson({ openerr => $err });
                    }
                }
                if (defined $v) {
                    $v = $v->numify if ref($v) eq 'version';
                } else {
                    $v = "";
                }
                print $v;
                exit;
            }
        }

        return $self->normalize_version($v);
    }

    # package PAUSE::pmfile
    sub normalize_version {
        my($self,$v) = @_;
        $v = "undef" unless defined $v;
        my $dv = Dumpvalue->new;
        my $sdv = $dv->stringify($v,1); # second argument prevents ticks
        $self->verbose(1,"sdv[$sdv]\n");

        return $v if $v eq "undef";
        return $v if $v =~ /^\{.*\}$/; # JSON object
        $v =~ s/^\s+//;
        $v =~ s/\s+\z//;
        return $v if $v =~ /_/;
        my $vv = version->new($v)->numify;
        if ($vv eq $v) {
            # the boring 3.14
        } else {
            my $forced = $self->force_numeric($v);
            if ($forced eq $vv) {
            } elsif ($forced =~ /^v(.+)/) {
                # rare case where a v1.0.23 slipped in (JANL/w3mir-1.0.10.tar.gz)
                $vv = version->new($1)->numify;
            } else {
                # warn "Unequal forced[$forced] and vv[$vv]";
                if ($forced == $vv) {
                    # the trailing zeroes would cause unnecessary havoc
                    $vv = $forced;
                }
            }
        }
        return $vv;
    }

    # package PAUSE::pmfile;
    sub force_numeric {
        my($self,$v) = @_;
        $v = CPAN::Version->readable($v);

        if (
            $v =~
            /^(\+?)(\d*)(\.(\d*))?/ &&
            # "$2$4" ne ''
            (
             defined $2 && length $2
             ||
             defined $4 && length $4
            )
           ) {
            my $two = defined $2 ? $2 : "";
            my $three = defined $3 ? $3 : "";
            $v = "$two$three";
        }
        # no else branch! We simply say, everything else is a string.
        $v;
    }

}

=comment

Now we have a table primeur and we have a new terminology:

people in table "perms" are co-maintainers or maintainers

people in table "primeur" are maintainers

packages in table "packages" live there independently from permission
tables.

packages in table "mods" have an official owner. That one overrules
both tables "primeur" and "perms".


P1.0 If there is a registered maintainer in mods, put him into perms
     unconditionally.

P2.0 If perms knows about this package but current user is not in
     perms for this package, return.

 P2.1 but if user is primeur, go on

 P2.2 but if there is no primeur, make this user primeur

P3.0 Give this user an entry in perms now, no matter how many there are.

P4.0 Work out how packages table needs to be updated.

 P4.1 We know this package: complicated UPDATE

 P4.2 We don't know it: simple INSERT



package in packages  package in primeur
         1                   1               easy         nothing add'l to do
         0                   0               easy         4.2
         1                   0               error        4.1
         0                   1           complicated(*)   4.2

(*) This happens when a package is removed from CPAN completely.


=cut


{
    package PAUSE::package;
    use vars qw($AUTOLOAD);

    sub verbose {
        my($self,$level,@what) = @_;
        my $parent = $self->parent;
        $parent->verbose($level,@what);
    }

    sub parent {
        my($self) = @_;
        $self->{FIO} || $self->{DIO};
    }

    sub DESTROY {}

    # package PAUSE::package;
    sub new {
        my($me) = shift;
        bless { @_ }, ref($me) || $me;
    }

    # package PAUSE::package;
    sub alert {
        my $self = shift;
        my $what = shift;
        my $parent = $self->parent;
        $parent->alert($what);
    }

    # package PAUSE::package;
    # return value nonsensical
    sub give_regdowner_perms {
        my $self = shift;
        my $dbh = $self->connect;
        my $package = $self->{PACKAGE};
        local($dbh->{RaiseError}) = 0;
        my $sth_mods = $dbh->prepare("SELECT userid
                                      FROM   mods
                                      WHERE  modid = ?");
        # warn "Going to execute [SELECT userid FROM mods WHERE modid = '$package']";
        $sth_mods->execute($package) or die "FAILED";
        if ($sth_mods->rows>0) { # make sure we regard the owner as the owner
            my($mods_userid) = $sth_mods->fetchrow_array;
            local($dbh->{RaiseError}) = 0;
            local($dbh->{PrintError}) = 0;
            my $query = "INSERT INTO perms (package, userid) VALUES (?,?)";
            my $ret = $dbh->do($query, {}, $package, $mods_userid);
            my $err = "";
            $err = $dbh->errstr unless defined $ret;
            $ret ||= "";
            $self->verbose(1,"into perms package[$package]mods_userid".
                           "[$mods_userid]ret[$ret]err[$err]\n");
        }
    }

    # perm_check: we're both guessing and setting.

    # P2.1: returns 1 if user is owner; makes him co-maintainer at the
    # same time

    # P2.0: otherwise returns false if the package is already known in
    # perms table AND the user is not among the co-maintainers

    # but if the package is not yet known in the perms table this makes
    # him co-maintainer AND returns 1

    # package PAUSE::package;
    sub perm_check {
        my $self = shift;
        my $dist = $self->{DIST};
        my $package = $self->{PACKAGE};
        my $pp = $self->{PP};
        my $dbh = $self->connect;

        my($userid) = $self->{USERID};

        my $ins_perms = "INSERT INTO perms (package, userid) VALUES ".
            "('$package', '$userid')";

        my($is_primeur) = $dbh->prepare(qq{SELECT package, userid
                                         FROM   primeur
                                         WHERE  package = ? AND userid = ?}
                                       );
        $is_primeur->execute($package,$userid);
        if ($is_primeur->rows) {

            local($dbh->{RaiseError}) = 0;
            local($dbh->{PrintError}) = 0;
            my $ret = $dbh->do($ins_perms);
            my $err = "";
            $err = $dbh->errstr unless defined $ret;
            $ret ||= "";
            # print "(primeur)ins_perms[$ins_perms]ret[$ret]err[$err]\n";

            return 1;           # P2.1, P3.0
        }

        my($has_primeur) = $dbh->prepare(qq{SELECT package
                                          FROM  primeur
                                          WHERE package = ?});
        $has_primeur->execute($package);
        if ($has_primeur->rows == 0) {
            my($has_owner) = $dbh->prepare(qq{SELECT modid
                                        FROM mods
                                        WHERE modid = ?});
            $has_owner->execute($package);
            if ($has_owner->rows == 0) {
                # package has neither owner in mods nor maintainer in primeur
                local($dbh->{RaiseError}) = 0;
                my $ret = $dbh->do($ins_perms);
                my $err = "";
                $err = $dbh->errstr unless defined $ret;
                $ret ||= "";
                $self->verbose(1,"(ownerless)ins_perms[$ins_perms]ret[$ret]err[$err]\n");

                return 1;       # P2.2, P3.0
            }
        }

        my($sth_perms) = $dbh->prepare(qq{SELECT package, userid
                                         FROM   perms
                                         WHERE  package = ?}
                                      );
        $sth_perms->execute($package);

        if ($sth_perms->rows) {

            # we have a package that is already known

            for ($package,
                 $pp->{version},
                 $dist,
                 $pp->{infile}) {
                $_ ||= '';
            }
            my($p,$owner,@owner);
            while (($p,$owner) = $sth_perms->fetchrow_array) {
                push @owner, $owner; # array for debugging statement
            }
            if ($dist =~ /$PAUSE::mldistwatch::ISA_REGULAR_PERL/) {
                # seems ok: perl is always right
            } elsif (! grep { $_ eq $userid } @owner) {
                # we must not index this and we have to inform somebody
                my $owner = eval { PAUSE::owner_of_module($package, $dbh) };
                $self->index_status($package,
                                    $pp->{version},
                                    $pp->{infile},
                                    PAUSE::mldistwatch::Constants::EMISSPERM,
                                    qq{Not indexed because permission missing.
Current registered primary maintainer is $owner.
Hint: you can always find the legitimate maintainer(s) on PAUSE under "View Permissions".},
                                   );
                $self->alert(qq{not owner:
  package[$package]
  version[$pp->{version}]
  file[$pp->{infile}]
  dist[$dist]
  userid[$userid]
  owners[@owner]
  owner[$owner]
});
                return;         # early return
            }

        } else {

            # package has no existence in perms yet, so this guy is OK

            local($dbh->{RaiseError}) = 0;
            my $ret = $dbh->do($ins_perms);
            my $err = "";
            $err = $dbh->errstr unless defined $ret;
            $ret ||= "";
            $self->verbose(1,"(uploader)ins_perms[$ins_perms]ret[$ret]err[$err]\n");

        }
        $self->verbose(1,sprintf( # just for debugging
                                 "02maybe: %-25s %10s %-16s (%s) %s\n",
                                 $package,
                                 $pp->{version},
                                 $pp->{infile},
                                 $pp->{filemtime},
                                 $dist
                                ));
        return 1;
    }

    # package PAUSE::package;
    sub connect {
        my($self) = @_;
        my $parent = $self->parent;
        $parent->connect;
    }

    # package PAUSE::package;
    sub disconnect {
        my($self) = @_;
        my $parent = $self->parent;
        $parent->disconnect;
    }

    # package PAUSE::package;
    sub mlroot {
        my($self) = @_;
        my $fio = $self->parent;
        $fio->mlroot;
    }

    # package PAUSE::package;
    sub examine_pkg {
        my $self = shift;

        my $dbh = $self->connect;
        my $package = $self->{PACKAGE};
        my $dist = $self->{DIST};
        my $pp = $self->{PP};
        my $pmfile = $self->{PMFILE};

        # should they be cought earlier? Maybe.
        if ($package !~ /\w/
            ||
            $package =~ /:/ && $package !~ /::/){
            delete $self->{FIO};    # circular reference
            return;
        }

        # set perms for registered owner in any case

        $self->give_regdowner_perms; # (P1.0)

        # Query all users with perms for this package

        unless ($self->perm_check){ # (P2.0&P3.0)
            delete $self->{FIO};    # circular reference
            return;
        }

        # Parser problem

        if ($pp->{version} && $pp->{version} =~ /^\{.*\}$/) { # JSON parser error
            my $err = JSON::jsonToObj($pp->{version});
            if ($err->{openerr}) {
                $self->index_status($package,
                                    "undef",
                                    $pp->{infile},
                                    PAUSE::mldistwatch::Constants::EOPENFILE,

                                    qq{The PAUSE indexer was not able to
             read the file. It issued the following error: C< $err->{openerr} >},
                                   );
            } else {
                $self->index_status($package,
                                    "undef",
                                    $pp->{infile},
                                    PAUSE::mldistwatch::Constants::EPARSEVERSION,

                                    qq{The PAUSE indexer was not able to
             parse the following line in that file: C< $err->{line} >

             Note: the indexer is running in a Safe compartement and
             cannot provide the full functionality of perl in the
             VERSION line. It is trying hard, but sometime it fails.
             As a workaround, please consider writing a proper
             META.yml that contains a 'provides' attribute (currently
             only supported by Module::Build) or contact the CPAN
             admins to investigate (yet another) workaround against
             "Safe" limitations.)},

                                   );
            }
            delete $self->{FIO};    # circular reference
            return;
        }

        # Sanity checks

        for (
             $package,
             $pp->{version},
             $dist
            ) {
            if (!defined || /^\s*$/ || /\s/){  # for whatever reason I come here
                delete $self->{FIO};    # circular reference
                return;            # don't screw up 02packages
            }
        }

        $self->checkin;
        delete $self->{FIO};    # circular reference
    }

    # package PAUSE::package;
    sub update_package {
        # we come here only for packages that have opack and package

        my $self = shift;
        my $sth_pack = shift;

        my $dbh = $self->connect;
        my $package = $self->{PACKAGE};
        my $dist = $self->{DIST};
        my $pp = $self->{PP};
        my $pmfile = $self->{PMFILE};
        my $fio = $self->{FIO};


        my($opack,$oldversion,$odist,$ofilemtime,$ofile) = $sth_pack->fetchrow_array;
        $self->verbose(1,"opack[$opack]oldversion[$oldversion]".
                       "odist[$odist]ofiletime[$ofilemtime]ofile[$ofile]\n");
        my $MLROOT = $self->mlroot;
        my $odistmtime = (stat "$MLROOT/$odist")[9];
        my $tdistmtime = (stat "$MLROOT/$dist")[9] ;
        # decrementing Version numbers are quite common :-(
        my $ok = 0;

        my $distorperlok = $dist !~ m|/perl|;
        # this dist is not named perl-something (lex ILYAZ)

        my $isaperl = $dist =~ /$PAUSE::mldistwatch::ISA_REGULAR_PERL/;

        $distorperlok ||= $isaperl;
        # or it is THE perl dist

        my($something1) = $dist =~ m|/perl(.....)|;
        # or it is called perl-something (e.g. perl-ldap) AND...
        my($something2) = $odist =~ m|/perl(.....)|;
        # and we compare against another perl-something AND...
        my($oisaperl) = $odist =~ /$PAUSE::mldistwatch::ISA_REGULAR_PERL/;
        # the file we're comparing with is not the perl dist

        $distorperlok ||= $something1 && $something2 &&
            $something1 eq $something2 && !$oisaperl;

        $self->verbose(1, "package[$package]infile[$pp->{infile}]".
                       "distorperlok[$distorperlok]oldversion[$oldversion]".
                       "odist[$odist]\n");

        # Until 2002-08-01 we always had
        # if >ver                                                 OK
        # elsif <ver
        # else
        #   if 0ver
        #     if <=old                                            OK
        #     else
        #   elsif =ver && <=old && ( !perl || perl && operl)      OK

        # From now we want to have the primary decision on isaperl. If it
        # is a perl, we only index if the other one is also perl or there
        # is no other. Otherwise we leave the decision tree unchanged
        # except that we can simplify the complicated last line to

        #   elsif =ver && <=old                                   OK

        # AND we need to accept falling version numbers if old dist is a
        # perl

        # relevant postings/threads:
        # http://www.xray.mpe.mpg.de/mailing-lists/perl5-porters/2002-07/msg01579.html
        # http://www.xray.mpe.mpg.de/mailing-lists/perl5-porters/2002-08/msg00062.html


        if (! $distorperlok) {
        } elsif ($isaperl) {
            if ($oisaperl) {
                if (CPAN::Version->vgt($pp->{version},$oldversion)) {
                    $ok++;
                } elsif (CPAN::Version->vgt($oldversion,$pp->{version})) {
                } elsif (CPAN::Version->vcmp($pp->{version},$oldversion)==0
                         &&
                         $tdistmtime >= $odistmtime) {
                    $ok++;
                }
            } else {
                if (CPAN::Version->vgt($pp->{version},$oldversion)) {
                    $self->index_status($package,
                                        $pp->{version},
                                        $pp->{infile},
                                        PAUSE::mldistwatch::Constants::EDUALOLDER,

                                        qq{Not indexed because $ofile
 seems to have a dual life in $odist. Although the other package is at
 version [$oldversion], the indexer lets the other dist continue to be
 the reference version, shadowing the one in the core. Maybe harmless,
 maybe needs resolving.},

                                   );
                } else {
                    $self->index_status($package,
                                        $pp->{version},
                                        $pp->{infile},
                                        PAUSE::mldistwatch::Constants::EDUALYOUNGER,

                                        qq{Not indexed because $ofile
 has a dual life in $odist. The other version is at $oldversion, so
 not indexing seems okay.},

                                   );
                }
            }
        } elsif (CPAN::Version->vgt($pp->{version},$oldversion)) {
            # higher VERSION here
            $self->verbose(1, "$package version better ".
                           "[$pp->{version} > $oldversion] $dist wins\n");
            $ok++;
        } elsif (CPAN::Version->vgt($oldversion,$pp->{version})) {
            # lower VERSION number here
            if ($odist ne $dist) {
                $self->index_status($package,
                                    $pp->{version},
                                    $pmfile,
                                    PAUSE::mldistwatch::Constants::EVERFALLING,
                                    qq{Not indexed because $ofile in $odist
has a higher version number ($oldversion)},
                                   );
                $self->alert(qq{decreasing VERSION number [$pp->{version}]
  in package[$package]
  dist[$dist]
  oldversion[$oldversion]
  pmfile[$pmfile]
}); # });
            } elsif ($oisaperl) {
                $ok++;          # new on 2002-08-01
            } else {
                # we get a different result now than we got in a previous run
                $self->alert("Taking back previous version calculation. odist[$odist]oversion[$oldversion]dist[$dist]version[$pp->{version}].");
                $ok++;
            }
        } else {

            # 2004-01-04: Stas Bekman asked to change logic here. Up
            # to rev 478 we did not index files with a version of 0
            # and with a falling timestamp. These strange timestamps
            # typically happen for developers who work on more than
            # one computer. Files that are not changed between
            # releases keep two different timestamps from some
            # arbitrary checkout in the past. Stas correctly suggests,
            # we should check these cases for distmtime, not filemtime.

            # so after rev. 478 we deprecate the EMTIMEFALLING constant

            if ($pp->{version} eq "undef"||$pp->{version} == 0) { # no version here,
                if ($tdistmtime >= $odistmtime) { # but younger or same-age dist
                    $self->verbose(1, "$package noversion comp $dist vs $odist: >=\n");
                    $ok++;
                } else {
                    $self->index_status(
                                        $package,
                                        $pp->{version},
                                        $pp->{infile},
                                        PAUSE::mldistwatch::Constants::EOLDRELEASE,
                                        qq{Not indexed because $ofile in $odist
also has a zero version number and the distro has a more recent modification time.}
                                       );
                }
            } elsif (CPAN::Version
                     ->vcmp($pp->{version},
                            $oldversion)==0) {    # equal version here
                $self->verbose(1, "$package version eq comp $dist vs $odist\n");
                if ($tdistmtime >= $odistmtime) { # but younger or same-age dist
                    $ok++;
                } else {
                    $self->index_status(
                                        $package,
                                        $pp->{version},
                                        $pp->{infile},
                                        PAUSE::mldistwatch::Constants::EOLDRELEASE,
                                        qq{Not indexed because $ofile in $odist
has the same version number and the distro has a more recent modification time.}
                                       );
                }
            } else {
                $self->verbose(1, "Nothing interesting in dist[$dist]package[$package]\n");
            }
        }


        if ($ok) {              # sanity check

            if (! $pp->{simile}
                &&
                $fio->simile($ofile,$package)
               ) {
                $self->verbose(1,
                               "Warning: we ARE NOT simile BUT WE HAVE BEEN ".
                               "simile some time earlier:\n");
                $self->verbose(1,Data::Dumper::Dumper($pp), "\n");
                $ok = 0;
            }
        }

        if ($ok) {

            my $query = qq{UPDATE packages SET version = ?, dist = ?, file = ?,
filemtime = ?, pause_reg = ? WHERE package = ?};
            $self->verbose(1,"Q: [$query]$pp->{version},$dist,$pp->{infile},$pp->{filemtime},$self->{TIME},$package\n");
            $dbh->do($query,
                     undef,
                     $pp->{version},
                     $dist,
                     $pp->{infile},
                     $pp->{filemtime},
                     $self->{TIME},
                     $package,
                    );
            $self->index_status($package,
                                $pp->{version},
                                $pp->{infile},
                                PAUSE::mldistwatch::Constants::OK,
                                "indexed",
                               );

        }

    }

    # package PAUSE::package;
    sub index_status {
        my($self) = shift;
        my $dio;
        if (my $fio = $self->{FIO}) {
            $dio = $fio->{DIO};
        } else {
            $dio = $self->{DIO};
        }
        $dio->index_status(@_);
    }

    # package PAUSE::package;
    sub insert_into_package {
        my $self = shift;
        my $dbh = $self->connect;
        my $package = $self->{PACKAGE};
        my $dist = $self->{DIST};
        my $pp = $self->{PP};
        my $pmfile = $self->{PMFILE};
        $self->verbose(1,"First time here, eh?\n");
        my $query = qq{INSERT INTO packages
 (package, version, dist, file, filemtime, pause_reg)
VALUES (?,?,?,?,?,?)
};
        $self->verbose(1,"Q: [$query]$package,$pp->{version},$dist,$pp->{infile},$pp->{filemtime},$self->{TIME}\n");
        $dbh->do($query,
                 undef,
                 $package,
                 $pp->{version},
                 $dist,
                 $pp->{infile},
                 $pp->{filemtime},
                 $self->{TIME},
                );
        $self->index_status($package,
                            $pp->{version},
                            $pp->{infile},
                            PAUSE::mldistwatch::Constants::OK,
                            "indexed",
                           );
    }

    # package PAUSE::package;
    # returns always the return value of print, so basically always 1
    sub checkin_into_primeur {
        my $self = shift;
        my $dbh = $self->connect;
        my $package = $self->{PACKAGE};
        my $dist = $self->{DIST};
        my $pp = $self->{PP};
        my $pmfile = $self->{PMFILE};

        # we cannot do that yet, first we must fill primeur with the
        # values we believe are correct now.

        # We come here, no matter if this package is in primeur or not. We
        # know, it must get in there if it isn't yet. No update, just an
        # insert, please. Should be similar to give_regdowner_perms(), but
        # this time with this user.

        # print ">>>>>>>>checkin_into_primeur not yet implemented<<<<<<<<\n";

        local($dbh->{RaiseError}) = 0;
        local($dbh->{PrintError}) = 0;

        my $userid = $self->{USERID} or die;
        my $query = "INSERT INTO primeur (package, userid) VALUES (?,?)";
        my $ret = $dbh->do($query, {}, $package, $userid);
        my $err = "";
        $err = $dbh->errstr unless defined $ret;
        $ret ||= "";
        $self->verbose(1,
                       "into primeur package[$package]userid[$userid]ret[$ret]".
                       "err[$err]\n");
    }

    # package PAUSE::package;
    sub checkin {
        my $self = shift;
        my $dbh = $self->connect;
        my $package = $self->{PACKAGE};
        my $dist = $self->{DIST};
        my $pp = $self->{PP};
        my $pmfile = $self->{PMFILE};

        $self->checkin_into_primeur; # called in void context!

        my $sth_pack = $dbh->prepare(qq{SELECT package, version, dist,
                                          filemtime, file
                                   FROM packages
                                   WHERE package = ?});

        $sth_pack->execute($package);


        if ($sth_pack->rows) {

            # We know this package from some time ago

            $self->update_package($sth_pack);

        } else {

            # we hear for the first time about this package

            $self->insert_into_package;

        }

    }
}

1;

__END__

=head1 NAME

mldistwatch - The infamous PAUSE indexer

=head1 SYNOPSIS

 mldistwatch [OPTIONS]

 OPTIONS:

 usually used by paused after upload:
   --pick=distro ...    distro is a full path
   --logfile=logfile    diag not to STDOUT but to this file

 useful if testing the indexer at home:
   --skip-locking       (bool) skip locking (e.g. reindex if already indexed)

 useful for testing:
   --rewrite            (bool) do not index, only rewrite the index files

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
skipped. No find() is taking place. Inexistant distros are not removed
from the database.

=head1 OVERVIEW

So we have distfilechecks, directorychecks and contentfilechecks.
Contentchecks have two parts, files and namespaces (packages). And we
have some sort of a scheduler that keeps track of what we have to do.

Classes contained in the script:

 PAUSE::mldistwatch       we could call it main. One object does all the
                          work

 PAUSE::mldistwatch::Constants
                          constants used for PAUSE::dist::index_status()

 PAUSE::dist              each distro we find is an object of this class

 PAUSE::pmfile            each *.pm file in each distro is one object of
                          this class

 PAUSE::package           each package statement per pm-file is an object
                          of this class


The methods alert() and verbose() exist in all classes. Only the two
in PAUSE::mldistwatch do something for real, the others just pass
their arguments up in the "stack" of objects. Similarly index_status
passes arguments up till they reach the PAUSE::dist object. From there
they are harvested in the mail_summary() method that sends a report to
the owner of the package



=cut

#Local Variables:
#mode: cperl
#cperl-indent-level: 4
#End:
