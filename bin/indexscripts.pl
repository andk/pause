#!/usr/local/bin/perl
# Build the scripts index for PAUSE
# Original author:  KSTAR
# Last modified:  $Date: 2003/12/13 05:52:51 $


# TODO:
# Full support for .tar, .tar.gz, .tgz, .bz, etc.
# Consolidate all verbose modes into one logging function.


# NOTES on data structures:
#
# %map:
#   Key:    uri of a script (or a file containing a script)
#   Value:  reference to a %pod
#
# %pod:
#   Key:    POD header name (e.g., `SCRIPT CATEGORIES', `README')
#   Value:  If Key is `README', then value is a string (the complete literal
#           contents of the POD section).
#           Otherwise, value is a reference to an array whose elements are
#           the contents of C<> markup (if available), or individual lines
#           of the POD section.
#   Key:    `.tarpath'
#   Value:  The filename as it appears in the tarball, if any.
#   Key:    SCRIPTNAME
#   Value:  The contents of the SCRIPTNAME POD section, _or_ the basename
#           of .tarpath, _or_ the basename of the uri.


my $VERSION = substr q$Revision: 1.33 $, 10;
my $Id = q$Id: indexscripts.pl,v 1.33 2003/12/13 05:52:51 kstar Exp $;

my $MAINTAINER =
    '<A HREF="mailto:kstar@cpan.org">Kurt Starsinic</A>';

use strict;
use lib '/home/k/PAUSE/lib';


use Getopt::Std;
use vars qw($opt_v);    # Verbose
use vars qw($opt_n);    # Don't update indices
use vars qw($opt_i);    # Ignore $SCRIPT_DB
use vars qw($opt_f);    # Force rebuild of $SCRIPT_DB
use vars qw($opt_d);    # Debugging -- do no harm, say much
use vars qw($opt_D);    # Directory in which to build (for debugging)
use vars qw($opt_S);    # Specify where to scan for the scripts
$opt_S  = 'df';         # Default is database and files
getopts('v:nifdD:s:S:');
$opt_f = 1 unless -t STDIN; # Temporary workaround


# Option consistency:
die "-n and -f are mutually exclusive\n" if defined $opt_n and defined $opt_f;
$opt_i = 1                               if defined $opt_n;


# Debugging:
if ($opt_d) {
    $opt_n  = 1;
    $opt_i  = 1;
    $opt_v  .= 'fcszp';
}

# Verbosity options:
if ($opt_v =~ /v/) {    # -vv means fully verbose
    $opt_v  = 'fcdszpP';
}

#    $opt_vf = 1 if s/f//g;  # List every file that's touched
#    $opt_vc = 1 if s/c//g;  # Information on categories
#    $opt_vd = 1 if s/d//g;  # Information on DB access
#    $opt_vs = 1 if s/s//g;  # Information on scripts
#    $opt_vz = 1 if s/z//g;  # Information on compressed files
#    $opt_vp = 1 if s/p//g;  # Show POD being scanned
#    $opt_vP = 1 if s/P//g;  # Show a lot on POD being scanned


use PAUSE ();
use File::Copy;
use Data::Dumper;
use DBI;
use Compress::Zlib;


my $SCRIPT_TMP  = "/home/kstar/etc/tmp";            # Scratchpad
my $SCRIPT_ROOT = defined($opt_D) ? $opt_D : $$PAUSE::Config{FTPPUB};
my $SCRIPT_TOC  = "$SCRIPT_ROOT/scripts/";
my $SCRIPT_DB   = "/home/kstar/etc/SCRIPT_DB";      # Data::Dumper output
use File::Path qw(make_path);
use File::Basename qw(dirname);
make_path dirname $SCRIPT_DB;


my (%KNOWN_KEYS) = (
    'SCRIPT CATEGORIES' => 1,
    'PREREQUISITES'     => 1,
    'OSNAMES'           => 1,
    'README'            => 1,
);


my $BRIEF_LIMIT = 220;   # see _brief()

unlink $SCRIPT_DB  if $opt_f;   # Re-index from scratch if `-f'

# Get a list of potential (new) scripts.
#    Normally, scan scriptlike files on CPAN that have been added
#    since the mtime of $SCRIPT_DB (minus one hour margin of error).
#    If -i, scan _all_ scriptlike files.
my $checkpoint  = defined($opt_i) ?
                  905477215       :                 # The Epoch
                  ([stat $SCRIPT_DB]->[9] - 3600);  # 3600 seconds = 1 hour
my $db    = DBI->connect(
    $$PAUSE::Config{MOD_DATA_SOURCE_NAME},
    $$PAUSE::Config{MOD_DATA_SOURCE_USER},
    $$PAUSE::Config{MOD_DATA_SOURCE_PW},
    { RaiseError => 1 }
) or Carp::croak("Can't DBI->connect():  $DBI::errstr");
debug('d', 'connected');

my $sth;
if ($opt_S =~ /d/) {
    my $query   = "select * from uris where dverified > '$checkpoint'";
    $sth        = $db->prepare($query);
    $sth->execute;
    debug('d', "DB:  executed $query");
}

my %map;    # The master data structure
eval { %map = %{ do $SCRIPT_DB } } unless $opt_i;


### KLUDGE
my (@Special)   = (
    { uriid => 'MUIR/scripts/find_used_modules.gz' },
);
sub _next_maybe_script
{
    my $record;

    if (defined $sth) {
        unless ($record = $sth->fetchrow_hashref) {
            $sth->finish;
            undef $sth;
        }

        debug('d', "Fetched $$record{uriid}");
    }

    if (!defined $record and $opt_S =~ /f/ and @Special) {
        $record = shift @Special;
    }

    if (defined $record) { return $record }
    else                 { return }
}


# Index all scripts:
while (my $record = _next_maybe_script()) {
    my $file    = $$PAUSE::Config{MLROOT} . "/" . $$record{uriid};
    my %pod;

    next unless -f $file;
    debug('f', $file);

    # For now, special-case non-tarred .gz files:
    if ($$record{uriid} =~ /^[^\.]*\.gz$/) {
        if (-f $file) {
            debug('z', "Found gz file $$record{uriid}");

            %pod    = depod($file, 'GUNZIP ME PLEASE');
        }
    } else {
        # Skip binaries (for now):
        next if -B $file;

        # Skip compressed files:
        next if $file =~ /\b(gz)|(tar)|(tgz)|(zip)|(hqx)$/;

        # Skip modules, patches, and RPM's:
        next if $file =~ /\b(pm)|(patch)|(rpm)$/;

        # Skip announcements, readme's, and other documentation:
        next if $file =~ /\b(announce)|(readme)|(txt)|(text)|(html)$/i;

        %pod    = depod($file) if -f $file;
    }

    debug('f', "  (contains POD)") if %pod;

    # If this is a script:
    if ($pod{'SCRIPT CATEGORIES'}) {
        my @categories = grep { /\S/ } @{$pod{'SCRIPT CATEGORIES'}};

        pop @categories while @categories > 3;  # Avoid `index-spamming'
        $pod{'SCRIPT CATEGORIES'} = \@categories;
        debug('p', "  (has categories @categories)");

        $map{$$record{uriid}} = \%pod;
    }
}

debug('d', "Disconnecting $db");
$db->disconnect;
debug('d', "Disconnected $db");


# Dump the master data structure:
open_or_die(*SCRIPT_DB, ">$SCRIPT_DB");
print SCRIPT_DB Dumper(\%map);
close SCRIPT_DB;
chmod 0666, $SCRIPT_DB;


my (%scripts, %hierarchy);

foreach my $uri (keys %map) {
    $scripts{$uri}  = 1;    # Note all scripts for alpha listing

    foreach (@{$map{$uri}->{'SCRIPT CATEGORIES'}}) {
        my $category_dir = category_dir($_);

        if ($category_dir) {
            $hierarchy{$category_dir}->{$uri} = 1;
        } else {
            debug('c', sprintf("! %-35s %s", $_, $uri));
        }
    }
}


debug('s', "Found scripts:", map { "   $_" } sort keys %scripts);

debug('c', "Script categories:");

foreach (sort keys %hierarchy) {
    debug('c', "    $_:");

    debug('c', map { "        $_" } sort keys %{$hierarchy{$_}});
}


mkdirs("$SCRIPT_TOC/new", 0777) or die("Could not mkdir $SCRIPT_TOC/new:  $!");

open_or_die(*TOC, $opt_n ? ">/dev/null" : ">$SCRIPT_TOC/new/index.html");
    print TOC
        "<HTML><HEAD><TITLE>Scripts on CPAN</TITLE></HEAD>\n",
        "<BODY><CENTER><H2>Welcome to the scripts repository.</H2></CENTER>\n",
        "<HR>We hope you enjoy your visit.  Please report problems,\n",
        "or make suggestions, to $MAINTAINER.<HR>\n",
        "<UL><H3>Scripts by category:</H3>\n";

    # TODO:  Only show the top level of the hierarchy; must be changed
    # before we have a deep tree structure!
    foreach (sort keys %hierarchy) {
        my $pretty_category = $_;
        $pretty_category =~ s!/! : !g;

        print TOC
            "<LI><A HREF='./$_/index.html'>",
            "$pretty_category</A></LI>\n";
    }

    print TOC
        "</UL>\n",
        "<HR>\n",
        "<H3>Scripts alphabetically:</H3>\n",
        "<TABLE BORDER=1>\n",
        "<TR><TH>Script name</TH><TH>README</TH></TR>\n";

    # TODO:  Break this out into separate, bite-sized pages;
    foreach (sort scripts_alpha keys %scripts) {
        my $readme = _brief($map{$_}->{'README'});
        $readme = '&nbsp;' unless $readme =~ /\S/;

        print TOC
            "<TR><TD><A HREF='../authors/id/$_'>",
            $map{$_}->{'SCRIPTNAME'},
            "</A></TD>\n",
            "<TD>$readme</TD></TR>\n";
    }
    print TOC "</TABLE>\n";

    print TOC
        "</UL>\n",
        "<P>This resource consists entirely of user submissions.\n",
        "If you wish to submit your own scripts, please see\n",
        "<A HREF='submitting.html'>the instructions.</A></P>\n",

        "<P><B>Note:</B>  If you're looking for a particular script\n",
        "which was added to CPAN prior to 1997, you'll find it\n",
        "<A HREF='legacy.html'>here.</A></P>\n",

        "<HR>$MAINTAINER<BR>\n",
        "Last modified: ", scalar localtime, "\n",
        "</BODY></HTML>\n";
close TOC;
chmod(0666, "$SCRIPT_TOC/new/index.html") unless $opt_n;


# Now create the index page for each node in the hierarchy tree.
# TODO:  Build intermediate nodes, even when they're empty.
foreach (sort keys %hierarchy) {
    my @scripts         = sort keys %{$hierarchy{$_}};
    my $pretty_category = $_;
    my $slashes         = tr{/}{/};
    $pretty_category    =~ s{/}{ : }g;

    open_or_die(*INDEX, $opt_n ? ">-" : ">$SCRIPT_TOC/new/$_/index.html");
        print INDEX
            "<HTML><HEAD><TITLE>Scripts Category ",
                "$pretty_category</TITLE></HEAD>\n",
            "<BODY><CENTER><H3>Scripts Category ",
                "$pretty_category</H3></CENTER>\n",
            "<HR><TABLE BORDER=1>\n",
            "<TR><TH>Scriptname</TH><TH>README</TH></TR>\n";

        foreach (@scripts) {
            my $prefix = ("../" x ($slashes + 2)) . "authors/id";
            my $readme = _brief($map{$_}->{'README'}, $BRIEF_LIMIT * 2);
            $readme = '&nbsp;' unless $readme =~ /\S/;

            print INDEX
                "<TR><TD><A HREF='$prefix/$_'>",
                $map{$_}->{'SCRIPTNAME'},
                "</A></TD>\n",
                "<TD>$readme</TD></TR>\n";
        }
        print INDEX "</TABLE>\n";

        print INDEX
            "<HR>$MAINTAINER<BR>\n",
            "Last modified: ", scalar localtime, "\n",
            "</BODY></HTML>\n";
    close INDEX;
    chmod(0666, "$SCRIPT_TOC/new/$_/index.html") unless $opt_n;
}


# XXX:  I think that this function is a little broken, but I'm not sure.
sub mkdirs
{
    my ($dir, $mode) = @_;

    if    (-d $dir)      { return 1 }
    elsif (-e $dir)      { return undef }
    elsif (-d "$dir/..") { return mkdir $dir, $mode }

    $dir =~ s:/[^/]*$::;

    return mkdirs($dir, $mode);
}


# Extract contents of POD sections as key (section name) and value (contents)
# Second parameter, if it evaluates to TRUE, means that this is a gzipped
# file (this is a temporary kludge).
sub depod
{
    my ($filename, $gunzip) = @_;
    my ($header, %body);
    my $gz                  = gzopen_or_die($filename) if $gunzip;
    my $line;

    if ($gunzip) { $gz = gzopen_or_die($filename) }
    else         { open_or_die(*DEPOD, "<$filename\0") }
        while ($gunzip ? $gz->gzreadline($line) : defined($line = <DEPOD>)) {
            $line   =~ s/\cM\cJ/\cJ/;           # DOS is bad.

            if ($line =~ /^=cut\b/) {
                $header = undef;
            } elsif ($line =~ /^=\S*\s*(.*)/) { # POD directive
                if (defined $KNOWN_KEYS{$1}) { $header = $1 }
                else                         { $header = undef }
            } elsif (length $header) {          # Contents of named POD section
                $body{$header} .= $line;
            }
        }
    if ($gunzip) { $gz->gzclose }
    else         { close DEPOD }

    debug('[pP]',
        "pod for $filename:",
         map { "  $_ => " . _brief($body{$_}) } sort keys %body);

    # Turn the functional sections from strings to lists:
    foreach (keys %body) {
        next if $_ eq 'README';

        my @items;

        debug('p', "Scanning $_ in $filename:");

        if (@items = ($body{$_} =~ /C<(.*?)>/g)) {  # Use contents of C<>
            debug('p', "  $#items <> in $filename/=$_");
            $body{$_} = \@items;
        } else {                                    # Use each line on its own
            $body{$_} = [ grep { /\S/ } split /\n/, $body{$_} ];
            debug('p', "  $#{$body{$_}} in $filename/=$_");
        }

        if (ref $body{$_}) {
            debug('p', "Body:  $filename=/$_ is array of $#{$body{$_}}");
        }
    }

    if (!defined $body{'SCRIPTNAME'}) {
        $filename =~ m!([^/]*)$!;
        $body{'SCRIPTNAME'} = $1;
    }

    debug('p', "Script $filename is named $body{'SCRIPTNAME'}");

    return %body;
}


# Return a reasonable-length version of a POD item, suitable for printing
sub _brief
{
    my ($item, $brief_limit)    = (@_, $BRIEF_LIMIT);

    if (length($item) > $brief_limit) {
        $item = substr($item, 0, $brief_limit-3) . "...";
    }

    $item =~ s!&!&amp;!g;
    $item =~ s! B< ( [^>]* ) > !\001$1\002!gx;
    $item =~ s! I< ( [^>]* ) > !\003$1\004!gx;
    $item =~ s! E<lt> !<!gx;
    $item =~ s! E<gt> !>!gx;
    $item =~ s!<!&lt;!g;
    $item =~ s!>!&gt;!g;
    # $item =~ s/ /&nbsp;/g;
    $item =~ s!\001!<B>!g; $item =~ s!\002!</B>!g;
    $item =~ s!\003!<I>!g; $item =~ s!\004!</I>!g;
    $item =~ s!^\n+!!;
    $item =~ s!\n+!<BR>!g;

    return $item;
}


# Used for sorting scriptnames embedded in uriid's:
sub scripts_alpha
{
    my ($script_a) = ($a =~ m:([^/]+)$:);
    my ($script_b) = ($b =~ m:([^/]+)$:);

    return uc($script_a) cmp uc($script_b);
}


sub open_or_die
{
    my ($handle, $filespec) = @_;

    debug('f', "Opening $filespec");

    open $handle, $filespec or die "Cannot open $filespec:  $!";
}


sub gzopen_or_die
{
    my ($filespec)  = @_;
    my $gzstream;

    debug('f', "Gzopening $filespec");

    $gzstream   = gzopen($filespec, 'rb')
        or die "Cannot open $filespec:  $gzerrno\n";

    return $gzstream;
}


sub category_dir
{
    my ($category)  = @_;
    my $dir         = "";

    # The namespace of categories is case-insensitive; both underscore
    # and space in the POD map to underscore in the filesystem.
    $category =~ s/ /_/g;
    $category = lc($category);

    while (length $category) {
        my ($node, $rest) = split '/', $category, 2;
        my $success = 0;

        opendir DIR, "$SCRIPT_TOC/new/$dir";
            foreach (readdir DIR) {
                if (lc($_) eq $node) {
                    if (length $dir) { $dir .= "/$_" }
                    else             { $dir .= $_ }

                    $success = 1;
                    last;
                }
            }
        closedir DIR;

        if ($success) { $category = $rest }
        else          { return undef }
    }

    return $dir;
}


sub debug
{
    my ($mode, @message)    = @_;

    if ($opt_v =~ $mode) {
        print ">> $mode:  ", join("\n", @message), "\n" if @message;
    }
}

