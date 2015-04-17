package Apache::HeavyCGI::IfModified;
use strict;
use base 'Class::Singleton';

use vars qw($VERSION);
$VERSION = sprintf "%d.%03d", q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/;

use HTTP::Date ();

sub header {
  my Apache::HeavyCGI::IfModified $self = shift;
  my Apache::HeavyCGI $mgr = shift;

  my $now = $mgr->time;
  my $r   = $mgr->{R};

  my $last_modified = $mgr->last_modified;
  $r->header_out('Date', HTTP::Date::time2str($now));

  if (my $ifmodisi = $r->header_in('If-Modified-Since')) {
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

Apache::HeavyCGI::IfModified - Within Apache::HeavyCGI return 304

=head1 SYNOPSIS

 require Apache::HeavyCGI::IfModified;
 push @{$mgr->{HANDLER}},
     "Apache::HeavyCGI::IfModified"; # $mgr is an Apache::HeavyCGI object

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

IfModified should be one of the last handlers in any Apache::HeavyCGI
environment, at least it must be processed after all the handlers that
might set the LAST_MODIFIED date.

=cut

