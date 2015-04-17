package Apache::HeavyCGI::UnmaskQuery;
use Apache::Constants qw(:common);
use constant AHU_DEBUG => 0;
use strict;
use vars qw($VERSION);
$VERSION = sprintf "%d.%03d", q$Revision: 1.11 $ =~ /(\d+)\.(\d+)/;


sub handler {
  my($r) = @_;
  my $uri = $r->uri;
  if ( my($u1,$u2) = $uri =~ / ^ ([^?]+?) ; ([^?]*) $ /x ) {
    $r->uri($u1);
    # $u2 =~ s/%..//g; # just testing
    $u2 =~ s/;/&/g if $u2 =~ /&/; # don't mix: bug in Apache::Request ?
    $r->args($u2);
    warn "UnmaskQuery(v$VERSION): u1[$u1]u2[$u2]" if AHU_DEBUG;
  } elsif ($uri =~ /\?/) {
    my $args = $r->args;
    if ($args =~ /&/ and $args =~ s/;/&/g) { # don't mix!
      $r->args($args);
      warn "UnmaskQuery(v$VERSION): args[$args]" if AHU_DEBUG;
    } else {
      warn "UnmaskQuery(v$VERSION): nothing" if AHU_DEBUG;
    }
  } elsif ( my($u1,$u2) = $uri =~ m/^(.*?)%3[Bb](.*)$/ ) {
    # protect against old proxies that escape volens nolens
    $r->uri($u1);
    $u2 =~ s/%3B/;/gi;
    $u2 =~ s/%26/;/gi; # &
    $u2 =~ s/%3D/=/gi;
    $r->args($u2);
    warn "UnmaskQuery(v$VERSION): oldproxy-u1[$u1]u2[$u2]"
	if 1||AHU_DEBUG;
  }

  DECLINED;
}

1;

__END__

=head1 NAME

Apache::HeavyCGI::UnmaskQuery - Allow queries without a questionmark

=head1 SYNOPSIS

  <Perl>
  require Apache::HeavyCGI::UnmaskQuery;
  $PerlPostReadRequestHandler = "Apache::HeavyCGI::UnmaskQuery";
  </Perl>

 -or-

  PerlModule Apache::HeavyCGI::UnmaskQuery
  PerlPostReadRequestHandler Apache::HeavyCGI::UnmaskQuery

=head1 DESCRIPTION

This Apache Handler can be used from apache 1.3 (when
post_read_request was introduced) upwards to turn a request that looks
like an ordinary static request to the unsuspecting observer into a
query that can be handled by the CGI or Apache::Request module or by
the $r->args method.

The reason why you might want to do this lies in the fact that many
cache servers in use today (1999) are configured wrongly in that they
disallow caching of URIs with a questionmark in them. By composing
URIs with a semicolon instead of a questionmark, these cache servers
can be tricked into working correctly.

Thus this handler replaces the first semicolon in any request for an
URI with a questionmark (unless that URI does already contain a
questionmark). As this is being done in the very early stage of
apache's handling phase, namely in a PerlPostReadRequestHandler, all
subsequent phases can be tricked into seeing the request as a query.

Unfortunately the last paragraph is not completely true. Apache 1.3.4
is not allowing C<%2F> (a slash in ASCII) and C<%00> (a binary 0) in
the I<path> section of the HTTP URI, only in the I<searchoart>
section. Apparently the URL is parsed before the during read_request....

    Breakpoint 1, 0x80b9d05 in ap_unescape_url ()
    (gdb) bt
    #0  0x80b9d05 in ap_unescape_url ()
    #1  0x80b5a56 in ap_some_auth_required ()
    #2  0x80b5fb0 in ap_process_request ()
    #3  0x80adbcd in ap_child_terminate ()
    #4  0x80add58 in ap_child_terminate ()
    #5  0x80adeb3 in ap_child_terminate ()
    #6  0x80ae490 in ap_child_terminate ()
    #7  0x80aecc3 in main ()
    (gdb) c


So if any parameter needs to contain a slash or a binary 0,
we must resort to a different escape method. Now it's turning
ridiculous quickly. I believe, this is a bug in apache and must be
fixed there. But what if the apche group doesn't listen to us?

Easy answer: don't escape slashes if you want to use this technique.
Don't dare to need binary nulls in your parameters. Until it is
figured out if apache group sees this as a bug or not.

=cut

