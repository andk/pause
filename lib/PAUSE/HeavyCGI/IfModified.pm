package PAUSE::HeavyCGI::IfModified;
use strict;
use base 'Class::Singleton';

use vars qw($VERSION);
$VERSION = sprintf "%d.%03d", q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/;

use HTTP::Date ();

sub header {
  my PAUSE::HeavyCGI::IfModified $self = shift;
  my PAUSE::HeavyCGI $mgr = shift;

  my $now = $mgr->time;
  my $req = $mgr->{REQ};

  my $last_modified = $mgr->last_modified;
  $mgr->{RES}->header('Date', HTTP::Date::time2str($now));

  if (my $ifmodisi = $req->header('If-Modified-Since')) {
    # warn "Got ifmodisi[$ifmodisi]";
    $ifmodisi =~ s/\;.*//;
    my $ret;
    if ($last_modified->http eq $ifmodisi) {
      $ret = 304;
    } else {
      my $ifmodisi_unix = HTTP::Date::str2time($ifmodisi);
      if (defined $ifmodisi_unix
	  &&
	  $ifmodisi_unix < $now
	  &&
	  $ifmodisi_unix >= $last_modified->unix
	 ) {
	$ret = 304;
      }
    }
    return $mgr->{DONE} = $ret if $ret;
  }
}

1;

=head1 NAME

PAUSE::HeavyCGI::IfModified - Within PAUSE::HeavyCGI return 304

=head1 SYNOPSIS

 require PAUSE::HeavyCGI::IfModified;
 push @{$mgr->{HANDLER}},
     "PAUSE::HeavyCGI::IfModified"; # $mgr is an PAUSE::HeavyCGI object

=head1 DESCRIPTION

If-modified-since is tricky. We have pages with very differing
last modification. Some are modified NOW, some are old, most are
MADE now but would have been just the same many hours ago.

Because it's the recipe that is used for the composition of a page, it
may well be that a page that has never been generated before,
nonetheless has a Last-Modified date in the past. The Last-Modified
header acts as a weak validator for cache activities, and the older a
document appears to be, the longer the cache will store it for us by
default. When the cache revisits us after it has got a valid
Last-Modified header, it will use an If-Modified-Since header and if
we carefully determine our own Last-Modified time, we can spare a lot
of processing by returning a Not Modified response instead of working.

IfModified should be one of the last handlers in any PAUSE::HeavyCGI
environment, at least it must be processed after all the handlers that
might set the LAST_MODIFIED date.

=cut

