#!/usr/local/perl-5.7.2@14354+anonok/bin/perl -w

eval 'exec /usr/local/perl-5.7.2@14354+anonok/bin/perl -w -S $0 ${1+"$@"}'
    if 0; # not running under some shell

#line 18

=head1 NAME

pause-rget.pl - an overworked version of lwp-rget for the PAUSE

=head1 SYNOPSIS

 lwp-rget [--verbose] [--depth=N] [--iis]
	  [--limit=N]
	  [--prefix=URL] [--referer=URL] [--sleep=N] <URL>
 lwp-rget --version

=head1 DESCRIPTION

I needed something like 

    wget --directory-prefix=perl -r -m -nr -nH \
         --cut-dirs=3 -np --reject "*=*,index.html" \
         http://www.ilyaz.org/software/perl


With the additional option for

         --max-days=1000    # do not download files older than 1000 days

I took Gisle's lwp-rget and hacked over it. I'm not feeding the
changes back to Gisle because they are really PAUSE-specific and I do
not want to go into Date/Time details with the max-days option.

Besides the --max-days we had to somehow care for --directory-prefix,
--mirror, --reject.

We did not have to add -nr, -nH, --cut-dirs, -np because rget had the
right behaviour anyway.

I removed --keepext, --auth and --tolower because we don't need them.

I made --nospaces the default and removed the option.

I made --hier the default and removed the option.

=cut

use strict;

use Getopt::Long    qw(GetOptions);
use URI::URL	    qw(url);
use LWP::MediaTypes qw(media_suffix);
use HTML::Entities  ();

use vars qw($VERSION);
use vars qw($MAX_DEPTH $MAX_DOCS $MAX_DAYS $PREFIX $REFERER $VERBOSE $QUIET $SLEEP $IIS);

my $progname = $0;
$progname =~ s|.*/||;  # only basename left
$progname =~ s/\.\w*$//; #strip extension if any

$VERSION = sprintf("%d.%02d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/);

#$Getopt::Long::debug = 1;
#$Getopt::Long::ignorecase = 0;

# Defaults
$MAX_DEPTH = 5;
$MAX_DOCS  = 50;

GetOptions('version'  => \&print_version,
	   'help'     => \&usage,
	   'depth=i'  => \$MAX_DEPTH,
	   'limit=i'  => \$MAX_DOCS,
           'max-days=i' => \$MAX_DAYS,
	   'verbose!' => \$VERBOSE,
	   'quiet!'   => \$QUIET,
	   'sleep=i'  => \$SLEEP,
	   'prefix:s' => \$PREFIX,
	   'referer:s'=> \$REFERER,
	   'iis'      => \$IIS,
	  ) || usage();

sub print_version {
    require LWP;
    my $DISTNAME = 'libwww-perl-' . LWP::Version();
    print <<"EOT";
This is lwp-rget version $VERSION ($DISTNAME)

Copyright 1996-1998, Gisle Aas.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
EOT
    exit 0;
}

my $start_url = shift || usage();
usage() if @ARGV;

require LWP::UserAgent;
my $ua = new LWP::UserAgent;
$ua->agent("$progname/$VERSION " . $ua->agent);
$ua->env_proxy;

unless (defined $PREFIX) {
    $PREFIX = url($start_url);	 # limit to URLs below this one
    eval {
	$PREFIX->eparams(undef);
	$PREFIX->equery(undef);
    };

    $_ = $PREFIX->epath;
    s|[^/]+$||;
    $PREFIX->epath($_);
    $PREFIX = $PREFIX->as_string;
}


my $SUPPRESS_REFERER;
$SUPPRESS_REFERER++ if ($REFERER || "") eq "NONE";

print <<"" if $VERBOSE;
START	  = $start_url
MAX_DEPTH = $MAX_DEPTH
MAX_DOCS  = $MAX_DOCS
MAX_DAYS  = $MAX_DAYS
PREFIX	  = $PREFIX

my $no_docs = 0;
my %seen = ();	   # mapping from URL => local_file

my $filename = fetch($start_url, undef, $REFERER);
print "$filename\n" unless $QUIET;

sub fetch
{
    my($url, $type, $referer, $depth) = @_;

    # Fix http://sitename.com/../blah/blah.html to
    #	  http://sitename.com/blah/blah.html
    $url = $url->as_string if (ref($url));
    while ($url =~ s#(https?://[^/]+/)\.\.\/#$1#) {}

    # Fix backslashes (\) in URL if $IIS defined
    $url = fix_backslashes($url) if (defined $IIS);

    $url = url($url) unless ref($url);
    $type  ||= 'a';
    # Might be the background attribute
    $type = 'img' if ($type eq 'body' || $type eq 'td');
    $depth ||= 0;

    # Print the URL before we start checking...
    my $out = (" " x $depth) . $url . " ";
    $out .= "." x (60 - length($out));
    print STDERR $out . " " if $VERBOSE;

    # Can't get mailto things
    if ($url->scheme eq 'mailto') {
	print STDERR "*skipping mailto*\n" if $VERBOSE;
	return $url->as_string;
    }

    # The $plain_url is a URL without the fragment part
    my $plain_url = $url->clone;
    $plain_url->frag(undef);

    # Check PREFIX, Gisle excluded <IMG ...> links, we do not
    if ($url->as_string !~ /^\Q$PREFIX/o) {
	print STDERR "*outsider*\n" if $VERBOSE;
	return $url->as_string;
    }

    # If we already have it, then there is nothing to be done
    my $seen = $seen{$plain_url->as_string};
    if ($seen) {
	my $frag = $url->frag;
	$seen .= "#$frag" if defined($frag);
	$seen = protect_frag_spaces($seen);
	print STDERR "$seen (again)\n" if $VERBOSE;
	return $seen;
    }

    # Too much or too deep
    if ($depth > $MAX_DEPTH) {
	print STDERR "*too deep*\n" if $VERBOSE;
	return $url;
    }
    if ($no_docs > $MAX_DOCS) {
	print STDERR "*too many*\n" if $VERBOSE;
	return $url;
    }

    # Fetch document
    $no_docs++;
    sleep($SLEEP) if $SLEEP;

    if ($MAX_DAYS) {
      my $headreq = HTTP::Request->new(HEAD => $url);
      my $headres = $ua->request($headreq);
      if ($headres->is_success) {
        my $lmodi = $headres->last_modified;
        require HTTP::Date;
        my $daysold = ($^T - HTTP::Date::str2time($lmodi))/86400;
        if ($daysold > $MAX_DAYS) {
          print STDERR "*too old*\n" if $VERBOSE;
          return $url->as_string;
        }
      } else {
	print STDERR $res->code . " " . $res->message . "\n" if $VERBOSE;
	$seen{$plain_url->as_string} = $url->as_string;
	return $url->as_string;
      }
    }

    my $name = find_name($url);
    # XXX Frueher $name bestimmen und dann $ua->mirror rufen

    my $req = HTTP::Request->new(GET => $url);
    # See: http://ftp.sunet.se/pub/NT/mirror-microsoft/kb/Q163/7/74.TXT
    $req->header ('Accept', '*/*') if (defined $IIS);  # GIF/JPG from IIS 2.0
    $req->referer($referer) if $referer && !$SUPPRESS_REFERER;
    my $res = $ua->request($req);

    # Check outcome
    if ($res->is_success) {
	my $doc = $res->content;
	my $ct = $res->content_type;
	print STDERR "$name\n" unless $QUIET;
	$seen{$plain_url->as_string} = $name;

	# If the file is HTML, then we look for internal links
	if ($ct eq "text/html") {
	    # Save an unprosessed version of the HTML document.	 This
	    # both reserves the name used, and it also ensures that we
	    # don't loose everything if this program is killed before
	    # we finish.
	    save($name, $doc);
	    my $base = $res->base;

	    # Follow and substitute links...
	    $doc =~
s/
  (
    <(img|a|body|area|frame|td)\b   # some interesting tag
    [^>]+			    # still inside tag (not strictly correct)
    \b(?:src|href|background)	    # some link attribute
    \s*=\s*			    # =
  )
    (?:				    # scope of OR-ing
	 (")([^"]*)"	|	    # value in double quotes  OR
	 (')([^']*)'	|	    # value in single quotes  OR
	    ([^\s>]+)		    # quoteless value
    )
/
  new_link($1, lc($2), $3||$5, HTML::Entities::decode($4||$6||$7),
           $base, $name, "$url", $depth+1)
/giex;
	   # XXX
	   # The regular expression above is not strictly correct.
	   # It is not really possible to parse HTML with a single
	   # regular expression, but it is faster.  Tags that might
	   # confuse us include:
	   #	<a alt="href" href=link.html>
	   #	<a alt=">" href="link.html">
	   #
	}
	save($name, $doc);
	return $name;
    } else {
	print STDERR $res->code . " " . $res->message . "\n" if $VERBOSE;
	$seen{$plain_url->as_string} = $url->as_string;
	return $url->as_string;
    }
}

sub new_link
{
    my($pre, $type, $quote, $url, $base, $localbase, $referer, $depth) = @_;

    $url = protect_frag_spaces($url);

    $url = fetch(url($url, $base)->abs, $type, $referer, $depth);
    $url = url("file:$url", "file:$localbase")->rel
	unless $url =~ /^[.+\-\w]+:/;

    $url = unprotect_frag_spaces($url);

    return $pre . $quote . $url . $quote;
}


sub protect_frag_spaces
{
    my ($url) = @_;

    $url = $url->as_string if (ref($url));

    if ($url =~ m/^([^#]*#)(.+)$/)
    {
      my ($base, $frag) = ($1, $2);
      $frag =~ s/ /%20/g;
      $url = $base . $frag;
    }

    return $url;
}


sub unprotect_frag_spaces
{
    my ($url) = @_;

    $url = $url->as_string if (ref($url));

    if ($url =~ m/^([^#]*#)(.+)$/)
    {
      my ($base, $frag) = ($1, $2);
      $frag =~ s/%20/ /g;
      $url = $base . $frag;
    }

    return $url;
}


sub fix_backslashes
{
    my ($url) = @_;
    my ($base, $frag);

    $url = $url->as_string if (ref($url));

    if ($url =~ m/([^#]+)(#.*)/)
    {
      ($base, $frag) = ($1, $2);
    }
    else
    {
      $base = $url;
      $frag = "";
    }

    $base =~ tr/\\/\//;
    $base =~ s/%5[cC]/\//g;	# URL-encoded back slash is %5C

    return $base . $frag;
}


sub translate_spaces
{
    my ($url) = @_;
    my ($base, $frag);

    $url = $url->as_string if (ref($url));

    if ($url =~ m/([^#]+)(#.*)/)
    {
      ($base, $frag) = ($1, $2);
    }
    else
    {
      $base = $url;
      $frag = "";
    }

    $base =~ s/^ *//;	# Remove initial spaces from base
    $base =~ s/ *$//;	# Remove trailing spaces from base

    $base =~ tr/ /_/;
    $base =~ s/%20/_/g; # URL-encoded space is %20

    return $base . $frag;
}


sub mkdirp
{
    my($directory, $mode) = @_;
    my @dirs = split(/\//, $directory);
    my $path = shift(@dirs);   # build it as we go
    my $result = 1;   # assume it will work

    unless (-d $path) {
	$result &&= mkdir($path, $mode);
    }

    foreach (@dirs) {
	$path .= "/$_";
	if ( ! -d $path) {
	    $result &&= mkdir($path, $mode);
	}
    }

    return $result;
}


sub find_name
{
    my($url, $type) = @_;
    #print "find_name($url, $type)\n";

    $url = translate_spaces($url);

    $url = url($url) unless ref($url);

    my $path = $url->path;


    # XXX localpath = remotepath
    #                 minus vorne remoteprefix (=z.Zt. prefix)
    #                 plus vorne localprefix

    # trim path until only the basename is left
    $path =~ s|(.*/)||;
    my $dirname = ".$1";
    if (! -d $dirname) {
	mkdirp($dirname, 0775);
    }

    my $extra = "";  # something to make the name unique
    my $suffix;

    $suffix = ($path =~ m/\.(.*)/) ? $1 : "";

    $path =~ s|\..*||;	# trim suffix
    $path = "index" unless length $path;

    while (1) {
	# Construct a new file name
	my $file = $dirname . $path . $extra;
	$file .= ".$suffix" if $suffix;
	# Check if it is unique
	return $file unless -f $file;

	# Try something extra
	unless ($extra) {
	    $extra = "001";
	    next;
	}
	$extra++;
    }
}


sub save
{
    my $name = shift;
    #print "save($name,...)\n";
    open(FILE, ">$name") || die "Can't save $name: $!";
    binmode FILE;
    print FILE $_[0];
    close(FILE);
}


sub usage
{
    die <<"";
Usage: $progname [options] <URL>
Allowed options are:
  --depth=N	    Maximum depth to traverse (default is $MAX_DEPTH)
  --max-days=N      Only files up to maximum number of days old are mirrored
  --referer=URI     Set initial referer header (or "NONE")
  --iis		    Workaround IIS 2.0 bug by sending "Accept: */*" MIME
		    header; translates backslashes (\\) to forward slashes (/)
  --limit=N	    A limit on the number documents to get (default is $MAX_DOCS)
  --version	    Print version number and quit
  --verbose	    More output
  --quiet	    No output
  --sleep=SECS	    Sleep between gets, ie. go slowly
  --prefix=PREFIX   Limit URLs to follow to those which begin with PREFIX

}


__END__

-------- lwp-mirror --------

use LWP::Simple qw(mirror is_success status_message $ua);
use Getopt::Std;

$progname = $0;
$progname =~ s,.*/,,;  # use basename only
$progname =~ s/\.\w*$//; #strip extension if any

$VERSION = sprintf("%d.%02d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/);

$opt_h = undef;  # print usage
$opt_v = undef;  # print version
$opt_t = undef;  # timeout

unless (getopts("hvt:")) {
    usage();
}

if ($opt_v) {
    require LWP;
    my $DISTNAME = 'libwww-perl-' . LWP::Version();
    die <<"EOT";
This is lwp-mirror version $VERSION ($DISTNAME)

Copyright 1995-1999, Gisle Aas.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
EOT
}

$url  = shift or usage();
$file = shift or usage();
usage() if $opt_h or @ARGV;

if (defined $opt_t) {
    $opt_t =~ /^(\d+)([smh])?/;
    die "$progname: Illegal timeout value!\n" unless defined $1;
    $timeout = $1;
    $timeout *= 60   if ($2 eq "m");
    $timeout *= 3600 if ($2 eq "h");
    $ua->timeout($timeout);
}

$rc = mirror($url, $file);

if ($rc == 304) {
    print STDERR "$progname: $file is up to date\n"
} elsif (!is_success($rc)) {
    print STDERR "$progname: $rc ", status_message($rc), "   ($url)\n";
    exit 1;
}
exit;


sub usage
{
    die <<"EOT";
Usage: $progname [-options] <url> <file>
    -v           print version number of program
    -t <timeout> Set timeout value
EOT
}
