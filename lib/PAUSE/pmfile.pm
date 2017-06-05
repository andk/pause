use strict;
use warnings;
package PAUSE::pmfile;
use vars qw($AUTOLOAD);
use version (); # to get $version::STRICT
use PAUSE ();

BEGIN { die "Version of version.pm too low ($version::VERSION), does not define STRICT"
            unless defined $version::STRICT }

sub parent {
    my($self) = @_;
    $self->{DIO};
}

sub DESTROY {}

sub verbose {
    my($self,$level,@what) = @_;
    PAUSE->log($self, $level, @what);
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
    $file =~ s|\.pm(?:\.PL)?||;
    my $ret = $package =~ m/\b\Q$file\E$/;
    $ret ||= 0;
    unless ($ret) {
        # Apache::mod_perl_guide stuffs it into Version.pm
        $ret = 1 if lc $file eq 'version';
    }
    $self->verbose(1,"Result of simile(): file[$file] package[$package] ret[$ret]\n");
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
        if ($self->{META_CONTENT}){
            my $no_index = $self->{META_CONTENT}{no_index}
                            || $self->{META_CONTENT}{private}; # backward compat
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
                                $self->verbose(1,"Skipping ppp[$ppp] due to ve[$ve]");
                                next MANI;
                            } else {
                                $self->verbose(1,"NOT skipping ppp[$ppp] due to ve[$ve]");
                            }
                        }
                    } else {
                        $v =~ s|::$||;
                        if ($ppp =~ /^$v$rest/){
                            $self->verbose(1,"Skipping ppp[$ppp] due to v[$v]");
                            next MANI;
                        } else {
                            $self->verbose(1,"NOT skipping ppp[$ppp] due to v[$v]");
                        }
                    }
                }
            } else {
                $self->verbose(1,"No keyword 'no_index' or 'private' in META_CONTENT");
            }
        } else {
            # $self->verbose(1,"no META_CONTENT"); # too noisy
        }
        push @res, $ppp;
    }
    $self->verbose(1,"Result of filter_ppps: res[@res]");
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

    unless ($self->version_from_meta_ok) {
        my $version;
        unless (eval { $version = $self->parse_version; 1 }) {
          $self->verbose(1, "error with version in $pmfile: $@");
          return;
        }

        $self->{VERSION} = $version;

        my $dist_is_perl = $self->{DIO}->isa_regular_perl($self->{DIO}{DIST});

        if ($self->{VERSION} =~ /^\{.*\}$/) {
            # JSON error message
        } elsif ($self->{VERSION} =~ /[_\s]/ && ! $dist_is_perl) {
            # If the pmfile seems to be a dev version, we skip it... but not if
            # it's in perl.  Historical example:  perl-5.18.0 contains POSIX
            # 1.32, but perl-5.20.0 contains 1.38_03.  We would then skip the
            # new one, leaving some packages pointing at an older version of
            # perl.
            #
            # We don't need to account for single- versus dual-life, because
            # the check for dual-life packages still applies elsewhere.
            # -- rjbs, 2015-04-18
            delete $self->{DIO};    # circular reference
            return;
        }
    }

    my($ppp) = $self->packages_per_pmfile;
    my @keys_ppp = $self->filter_ppps(sort keys %$ppp);
    $self->verbose(1,"Will check keys_ppp[@keys_ppp]\n");

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
                  META_CONTENT => $self->{META_CONTENT},
                  MAIN_PACKAGE => $self->{MAIN_PACKAGE},
                  );

        $pio->examine_pkg;

    }                       # end foreach package

    delete $self->{DIO};    # circular reference

}

# package PAUSE::pmfile
sub version_from_meta_ok {
    my($self) = @_;
    return $self->{VERSION_FROM_META_OK} if exists $self->{VERSION_FROM_META_OK};
    $self->{VERSION_FROM_META_OK} = $self->{DIO}->version_from_meta_ok;
}

# package PAUSE::pmfile;
sub packages_per_pmfile {
    my $self = shift;

    my $ppp = {};
    my $pmfile = $self->{PMFILE};
    my $filemtime = $self->{MTIME};
    my $version = $self->{VERSION};

    $DB::single++;
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
        if ($pline =~ /^__(?:END|DATA)__\b/
            and $pmfile !~ /\.PL$/   # PL files may well have code after __DATA__
            ){
            last PLINE;
        }

        my $pkg;
        my $strict_version;

        if (
            $pline =~ m{
                      (.*)
                      (?<![*\$\\@%&]) # no sigils
                      \bpackage\s+
                      ([\w\:\']+)
                      \s*
                      (?: $ | [\}\;] | \{ | \s+($version::STRICT) )
                    }x) {
            $pkg = $2;
            $strict_version = $3;
            if ($pkg eq "DB"){
                # XXX if pumpkin and perl make him comaintainer! I
                # think I always made the pumpkins comaint on DB
                # without further ado (?)
                next PLINE;
            }
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
                if ($self->version_from_meta_ok) {
                    my $provides = $self->{DIO}{META_CONTENT}{provides};
                    if (exists $provides->{$pkg}) {
                        if (exists $provides->{$pkg}{version}) {
                            my $v = $provides->{$pkg}{version};
                            if ($v =~ /[_\s]/){   # ignore developer releases and "You suck!"
                                next PLINE;
                            }

                            unless (eval { $version = $self->normalize_version($v); 1 }) {
                              $self->verbose(1, "error with version in $pmfile: $@");
                              next;
                            }
                            $ppp->{$pkg}{version} = $version;
                        } else {
                            $ppp->{$pkg}{version} = "undef";
                        }
                    }
                } else {
                    if (defined $strict_version){
                        $ppp->{$pkg}{version} = $strict_version ;
                    } else {
                        $ppp->{$pkg}{version} = defined $version ? $version : "";
                    }
                    no warnings 'numeric';

                    $ppp->{$pkg}{version} =
                        $version
                            if ($version||0)
                                > $ppp->{$pkg}{version} ||
                                    ($version||"")
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
            last if /^__(?:END|DATA)__\b/; # fails on quoted __END__ but this is rare -> __END__ in the middle of a line is rarer
            chop;

            if (my ($ver) = /package \s+ \S+ \s+ (\S+) \s* [;{]/x) {
              # XXX: should handle this better if version is bogus -- rjbs,
              # 2014-03-16
              return $ver if version::is_lax($ver);
            }

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
    # $self->disconnect; # no guarantee that the connection survives the fork!

    {

        package main; # seems necessary

        my($pid,$kid);
        die "Can't fork: $!" unless defined($pid = open($kid, "-|"));
        if ($pid) {         # parent
            $v = <$kid>;
            # warn ">>>>>>>>read v[$v]<<<<<<<<";
            close $kid;
        } else {
            $self->connect->{InactiveDestroy} = 1;
            my($gnam,$gpw,$gid,$gmem) = getgrnam($PAUSE::Config->{ML_CHOWN_GROUP});
            die "Could not determine GID of $PAUSE::Config->{ML_CHOWN_GROUP}" unless defined $gid;
            my($uname,$upw,$uid,$ugid,$q,$c,$gcos,$udir,$ushell) =
                getpwnam($PAUSE::Config->{ML_CHOWN_USER});
            die "Could not determine UID of $PAUSE::Config->{ML_CHOWN_USER}" unless defined $uid;
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
            $comp->permit(":base_math");
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
    $self->verbose(1,"Result of normalize_version: sdv[$sdv]\n");

    return $v if $v eq "undef";
    return $v if $v =~ /^\{.*\}$/; # JSON object
    $v =~ s/^\s+//;
    $v =~ s/\s+\z//;
    if ($v =~ /_/) {
        # XXX should pass something like EDEVELOPERRELEASE up e.g.
        # SIXTEASE/XML-Entities-0.0306.tar.gz had nothing but one
        # such modules and the mesage was not helpful that "nothing
        # was found".
        return $v ;
    }
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

1;

