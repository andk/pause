use strict;
use warnings;
package PAUSE::pmfile;
use vars qw($AUTOLOAD);
use version (); # to get $version::STRICT
use PAUSE::Indexer::Errors;

use PAUSE::Logger '$Logger';

use PAUSE ();

BEGIN { die "Version of version.pm too low ($version::VERSION), does not define STRICT"
            unless defined $version::STRICT }

sub parent {
    my($self) = @_;
    $self->{DIO};
}

sub dist { $_[0]{DIO} }
sub hub  { $_[0]{DIO}{HUB} }

sub DESTROY {}

# package PAUSE::pmfile;
sub new {
    my($me) = shift;
    bless { @_ }, ref($me) || $me;
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
    my($self, @package_names) = @_;
    my @res;

    # the name "private" is there for backwards compatibility
    my $no_index = $self->{META_CONTENT} &&
        ($self->{META_CONTENT}{no_index} || $self->{META_CONTENT}{private});

    unless ($no_index && ref $no_index eq 'HASH') {
        # There's no no_index directive, or it's bogus.  We'll keep every
        # package!
        return @package_names;
    }

    # very similar code is in PAUSE::dist::filter_pms
    PACKAGE: for my $pkg ( @package_names ) {
        my %map = (
          package   => qr{\z},
          namespace => qr{::},
        );

        TYPE: for my $type (qw(package namespace)) {
            next TYPE unless my $rules = $no_index->{$type};

            my $rest = $map{$type};
            $rules = [$rules] unless ref $rules;

            for my $rule (@$rules) {
                $rule =~ s|::$||;

                if ($pkg =~ /^\Q$rule\E$rest/) {
                    $Logger->log("no_index rule on $type $rule; skipping $pkg");
                    next PACKAGE;
                } else {
                    $Logger->log_debug("no_index rule on $type $rule; NOT skipping $pkg");
                }
            }
        }

        push @res, $pkg;
    }

    return @res;
}

# package PAUSE::pmfile;
sub examine_fio {
    # fio: file object
    my ($self, $ctx) = @_;

    my $dist = $self->{DIO}{DIST};
    my $dbh = $self->connect;
    my $pmfile = $self->{PMFILE};

    local $Logger = $Logger->proxy({ proxy_prefix => "$pmfile: " });

    my($filemtime) = (stat $pmfile)[9];
    $self->{MTIME} = $filemtime;

    my $file_version;
    unless ($self->version_from_meta_ok($ctx)) {
        unless (eval { $file_version = $self->parse_version; 1 }) {
          my $error = $@;
          $Logger->log([ "error with version: %s", $error ]);
          return;
        }

        my $version = $file_version->{version};
        my $dist_is_perl = PAUSE::isa_regular_perl($self->{DIO}{DIST});

        if (defined $version && $version =~ /[_\s]/ && ! $dist_is_perl) {
            # If the pmfile seems to be a dev version, we skip it... but not if
            # it's in perl.  Historical example:  perl-5.18.0 contains POSIX
            # 1.32, but perl-5.20.0 contains 1.38_03.  We would then skip the
            # new one, leaving some packages pointing at an older version of
            # perl.
            #
            # We don't need to account for single- versus dual-life, because
            # the check for dual-life packages still applies elsewhere.
            # -- rjbs, 2015-04-18
            $Logger->log("skipping file because of dev version: $version");

            delete $self->{DIO};    # circular reference
            return;
        }
    }

    my ($ppp) = $self->packages_per_pmfile($ctx, $file_version);
    my @package_names = $self->filter_ppps(sort keys %$ppp);

    unless (@package_names) {
        $Logger->log("no files left after filtering");
        return;
    }

    $Logger->log([ "will examine packages: %s", \@package_names ]);

    #
    # Immediately after each package (pmfile) examined contact
    # the database
    #

    my @packages;
    for my $package_name (@package_names) {
        # What do we need? dio, fio, pmfile, time, dist, dbh, alert?
        my $pio = PAUSE::package->new(
            PACKAGE => $package_name,
            DIST => $dist,
            PP => $ppp->{$package_name},  # hash containing
                                          # version
            PMFILE => $pmfile,
            FIO => $self,
            USERID => $self->{USERID},
            META_CONTENT => $self->{META_CONTENT},
            MAIN_PACKAGE => $self->{MAIN_PACKAGE},
        );

        push @packages, $pio;
    }

    $self->{DIO}->index_packages($ctx, \@packages);

    delete $self->{DIO};    # circular reference
}

# package PAUSE::pmfile
sub version_from_meta_ok {
    my ($self, $ctx) = @_;
    return $self->{VERSION_FROM_META_OK} if exists $self->{VERSION_FROM_META_OK};
    $self->{VERSION_FROM_META_OK} = $self->{DIO}->version_from_meta_ok($ctx);
}

# package PAUSE::pmfile;
sub packages_per_pmfile {
    my ($self, $ctx, $file_version) = @_;

    my $ppp = {};
    my $pmfile = $self->{PMFILE};
    my $filemtime = $self->{MTIME};

    # $file_version is the result of parse_version, or undef if the versions
    # come from META instead.  If it's an error, every package that would have
    # taken the file's version gets the error instead.
    my $version       = $file_version && $file_version->{version};
    my $version_error = $file_version && $file_version->{error};

    $DB::single++;
    open my $fh, "<", "$pmfile" or return $ppp;

    local $/ = "\n";
    my $inpod = 0;

    my $checked_bom;
    my $package_or_class = 'package';
    local $_;
  PLINE: while (<$fh>) {
        chomp;
        my($pline) = $_;
        unless ($checked_bom) {
            $pline =~ s/\A(?:\x00\x00\xfe\xff|\xff\xfe\x00\x00|\xfe\xff|\xff\xfe|\xef\xbb\xbf)//;
            $checked_bom = 1;
        }
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

=pod
        # hide in the pod block until 'class' is added to a version bundle
        if ($pline =~ /^[\s\{;]*use\s(+v?5\.[0-9]+)/) {
            my $version = $1;
            my $version_bundle_for_class = version->parse("v5.xx.xx");
            if (eval { version->parse($version) >= $version_bundle_for_class) {
                $package_or_class = 'package|class|role';
            }
            next PLINE;
        }
=cut

        # use feature 'class'; enables class (and role, though not implemented yet)
        if ($pline =~ /^[\s\{;]*use\s+(?:feature|experimental)\s+[^;]+\b(?:class|all)[^;]*;/) {
            $package_or_class = 'package|class';
        }
        if ($pline =~ /^[\s\{;]*use\s+(?:Feature::Compat::Class)[^;]*;/) {
            $package_or_class = 'package|class';
        }
        # Object::Pad is special-cased; let's ignore other modules that are too old or less known
        if ($pline =~ /^[\s\{;]*use\s+(?:Object::Pad)[^;]*;/) {
            $package_or_class = 'package|class|role';
        }

        my $pkg;
        my $strict_version;

        if (
            $pline =~ m{
                      ^
                      [\s\{;]*
                      \b(?:$package_or_class)\s+
                      ([\w\:\']+)
                      \s*
                      (?: $ | [\}\;\:] | \{ | \s+($version::STRICT) )
                    }x) {
            $pkg = $1;
            $strict_version = $2;
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
            next PLINE if $pkg =~ /^Local::/; # Local::*
            next PLINE if $pkg eq "Local"; # Local
            # Perl::Critic::Policy::TestingAndDebugging::ProhibitShebangWarningsArg
            # database for modid in mods, package in packages, package in perms
            # alter table mods modify modid varchar(128) binary NOT NULL default '';
            # alter table packages modify package varchar(128) binary NOT NULL default '';
            next PLINE if length($pkg) > 128;
            #restriction
            $ppp->{$pkg}{parsed}++;
            $ppp->{$pkg}{infile} = $pmfile;
            if (PAUSE->basename_matches_package($pmfile,$pkg)) {
                $ppp->{$pkg}{basename_matches_package} = $pmfile;
                if ($self->version_from_meta_ok($ctx)) {
                    my $provides = $self->{DIO}{META_CONTENT}{provides};
                    if (exists $provides->{$pkg}) {
                        if (defined $provides->{$pkg}{version}) {
                            my $v = $provides->{$pkg}{version};
                            if ($v =~ /[_\s]/){   # ignore developer releases and "You suck!"
                                next PLINE;
                            }

                            unless (eval { $version = $self->normalize_version($v); 1 }) {
                              my $error = $@;
                              $Logger->log([ "error with version: $error" ]);
                              next;
                            }
                            $ppp->{$pkg}{version} = $version;
                        } else {
                            if (exists $provides->{$pkg}) {
                                $Logger->log("spec violation: meta provides for $pkg has an explicit undef");
                            }
                            $ppp->{$pkg}{version} = "undef";
                        }
                    }
                } else {
                    if (defined $strict_version){
                        $ppp->{$pkg}{version} = $strict_version ;
                    } elsif ($version_error) {
                        $ppp->{$pkg}{version} = "undef";
                        $ppp->{$pkg}{version_error} = $version_error;
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
            } else {        # not basename_matches_package
                #### it comes later, it would be nonsense
                #### to set to "undef". MM_Unix gives us
                #### the best we can reasonably consider
                unless (defined $ppp->{$pkg}{version} &&
                        length($ppp->{$pkg}{version})) {
                    if ($version_error) {
                        $ppp->{$pkg}{version} = "undef";
                        $ppp->{$pkg}{version_error} = $version_error;
                    } else {
                        $ppp->{$pkg}{version} = $version;
                    }
                }
            }
            $ppp->{$pkg}{filemtime} = $filemtime;
            $ppp->{$pkg}{pause_reg} = time;
        } else {
            # $Logger->log_debug("no pkg found");
        }
    }

    $fh->close;
    $ppp;
}

# These are used to recognize a $VERSION assignment whose value can be known
# without running it.  The line must be a literal assignment, or it's refused.
my $VERSION_LHS = qr{
    # Neither "my" nor "local" can set the package's $VERSION:  a lexical is a
    # different variable, and a file-level "local" is undone when the require
    # finishes.  So only "our" is allowed.
    (?: our )? \s* \(? \s*
    \$ (?: [\w:']* (?: :: | ' ) )? VERSION
    \s* \)?
}x;

# plain - single quotes or "q" qlop or double quotes or "qq" qlop: but in all
#         cases, the quoted content is exact: no interpolation or escaping to
#         undo; no version can contain a backslash or apostrophe anyway
# num   - a decimal numeric value, including the weird (to me) .5
my $VERSION_LITERAL = qr{
    ' (?<plain> [^'\\]* ) '
  | " (?<plain> [^"\\\$\@]* ) "
  | \b q \s* (?: \{ (?<plain> [^{}\\]* ) \}
               | \( (?<plain> [^()\\]* ) \)
               | \[ (?<plain> [^\[\]\\]* ) \]
               | <  (?<plain> [^<>\\]* )  > )
  | \b qq \s* (?: \{ (?<plain> [^{}\\\$\@]* ) \}
                | \( (?<plain> [^()\\\$\@]* ) \)
                | \[ (?<plain> [^\[\]\\\$\@]* ) \]
                | <  (?<plain> [^<>\\\$\@]* )  > )
  | (?<num> (?= \.? [0-9] ) (?: 0 | [1-9][0-9_]* )? (?: \. [0-9_]* )? )
}x;

# call - a call to the version.pm constructor, which we know will be safe to
#        turn into our own call to version.pm, because we know the argument
#        must match a VERSION_LITERAL form above
my $VERSION_LINE = qr{
    \A
    (?: \s | [{;] | \b BEGIN \s* \{ | \b (?: use | no | package ) \b [^;]* ; )*
    $VERSION_LHS \s* = \s*
    (?: \$ (?: [\w:']* (?: :: | ' ) )? VERSION \s* = \s* )?
    (?:
        (?<call> version \s* -> \s* (?: declare | new | parse ) | (?: version:: )? qv )
        \s* \( \s* $VERSION_LITERAL \s* \)
      | \( \s* $VERSION_LITERAL \s* \)
      | $VERSION_LITERAL
    )
    [\s;}]*
    (?: \# .* )?
    \z
}x;

=head2 static_version_from_file

  my $result = PAUSE::pmfile::static_version_from_file($filename);

This finds the line in the file that sets the module's version, the same way
ExtUtils::MakeMaker does, and works out the version it sets, without
evaluating anything.  The result is a hashref with one of these keys:

  version - the version found, or the string "undef" if there wasn't one
  refused - the line setting the version, which wasn't a literal assignment
  openerr - the error from trying to open the file

=cut

sub static_version_from_file {
    my ($parsefile) = @_;

    open(my $fh, "<", $parsefile) or return { openerr => "$!" };

    local $/ = "\n";
    my $inpod = 0;
    my $package_or_class = 'package';
    local $_;
    while (<$fh>) {
        $inpod = /^=(?!cut)/ ? 1 : /^=cut/ ? 0 : $inpod;
        next if $inpod || /^\s*#/;
        last if /^__(?:END|DATA)__\b/; # fails on quoted __END__ but this is rare -> __END__ in the middle of a line is rarer
        chop;

=pod
        # hide in the pod block until 'class' is added to a version bundle
        if (/^[\s\{;]*use\s(+v?5\.[0-9]+)/) {
            my $version = $1;
            my $version_bundle_for_class = version->parse("v5.xx.xx");
            if (eval { version->parse($version) >= $version_bundle_for_class) {
                $package_or_class = 'package|class|role';
            }
            next;
        }
=cut

        # use feature 'class'; enables class (and role, though not implemented yet)
        if (/^[\s\{;]*use\s+(?:feature|experimental)\s+[^;]+\b(?:class|all)[^;]*;/) {
            $package_or_class = 'package|class';
        }
        if (/^[\s\{;]*use\s+(?:Feature::Compat::Class)[^;]*;/) {
            $package_or_class = 'package|class';
        }
        # Object::Pad is special-cased; let's ignore other modules that are too old or less known
        if (/^[\s\{;]*use\s+(?:Object::Pad)[^;]*;/) {
            $package_or_class = 'package|class|role';
        }

        if (my ($ver) = /^[\s\{;]*(?:$package_or_class) \s+ \S+ \s+ (\S+) \s* [:;{]/x) {
          # XXX: should handle this better if version is bogus -- rjbs,
          # 2014-03-16
          return { version => $ver } if version::is_lax($ver);
        }

        # We only care about lines that appear to be assignments to, but
        # not comparisons to, VERSION.  An assignment that appears only in a
        # trailing comment doesn't count.  Finding the comment is
        # approximate:  the "#" in $#array is skipped, but a "#" inside a
        # string earlier on the line would hide the assignment after it.
        # Neither case appears in the version lines on CPAN today.
        my $code = s/(?<!\$)#.*//r;
        next unless $code =~ /([\$*])(([\w\:\']*)\bVERSION)\b.*(?<![!><=])\=(?![=>])/;

        return _static_version_from_line($_);
    }

    return { version => "undef" };
}

sub _static_version_from_line {
    my ($line) = @_;

    return { refused => $line } unless $line =~ $VERSION_LINE;
    my %match = %+;

    my $value = defined $match{plain} ? $match{plain}
              :                         0 + ($match{num} =~ tr/_//dr);

    return { version => $value } unless $match{call};

    my ($method) = $match{call} =~ /(\w+)\z/;
    my $object = eval {
        $method eq 'qv' ? version::qv($value) : version->$method($value);
    };

    # A version object for 0 is false, so we can't just test its truth.
    return { refused => $line } unless defined $object;
    return { version => $object->numify };
}

=head2 parse_version

  my $result = $pmfile->parse_version;

This returns a hashref with exactly one key, either C<version>, holding the
file's normalized version, or C<error>, holding the package error (from
PKGERROR) to report for every package that would have taken the file's
version.

=cut

# package PAUSE::pmfile;
sub parse_version {
    my ($self) = @_;

    my $result = static_version_from_file($self->{PMFILE});

    # TODO: get $result->{openerr} back in here, I guess?
    return { error => PKGERROR('version_openerr') }
        if exists $result->{openerr};

    return { error => PKGERROR(version_parse => { line => $result->{refused} }) }
        if exists $result->{refused};

    # If the author wrote
    #
    #   $VERSION = 0.000001
    #
    # ...instead of...
    #
    #   $VERSION = '0.000001'
    #
    # ...then the static parser numifies the literal, as perl would.  That's
    # bad, because we lose fidelity.  Sometimes this only means that 1.100
    # becomes 1.1, but the worse case is when a version like 0.000001 becomes
    # 1e-06, which can't be turned into a version object with version->new.
    #
    # When the version looks like scientific notation, we report it to the
    # author instead of letting normalize_version die and silently skipping
    # the file.
    #
    # -- rjbs, 2023-04-28
    return { error => PKGERROR(version_numeric_literal => { version => $result->{version} }) }
        if $result->{version} =~ /\A[0-9](?:\.[0-9]+)?e[-+]?[0-9]+\z/a;

    return { version => $self->normalize_version($result->{version}) };
}

# package PAUSE::pmfile
sub normalize_version {
    my($self,$v) = @_;
    $v = "undef" unless defined $v;
    my $dv = Dumpvalue->new;
    my $sdv = $dv->stringify($v,1); # second argument prevents ticks
    $Logger->log("result of normalize_version: $sdv");

    return $v if $v eq "undef";
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

