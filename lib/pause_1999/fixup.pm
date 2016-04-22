#!/usr/bin/perl -- -*- Mode: cperl; -*-
package pause_1999::fixup;
use strict;
use HTTP::Status qw(:constants);
our $VERSION = "85";

=comment

All Location below /pause share this FixupHandler. All we want to
achieve is that these mappings are in effect:

    /pause              redir=> /pause/query   CASE 1
    /pause/             trans=> /pause/query   CASE 2
    /pause/query        OK                     CASE 3
    /pause/authenquery  OK                     CASE 3

I have the suspicion that this would be easier with a completely
different approach, but as it works, I do not investigate further now.

=cut

sub handler {
  my $req = shift;
  # return HTTP_OK unless $r->is_initial_req;
  my $uri = $req->request_uri;
  my $location = '/pause'; # $r->location;

  # CASE 3

#  return DECLINED if $location =~ /query/;

  # warn "uri[$uri]location[$location] (Question was, does location ever match /query/?)";
  if ($uri eq $location) {

    # CASE 1

    my $redir = $req->base;
    my $is_ssl = $req->header("X-pause-is-SSL") || 0;
    if ($is_ssl) {
      $redir->scheme("https");
    }
    $redir->path("$location/query");
    my $res = $req->new_response(HTTP_MOVED_PERMANENTLY);
    $res->header("Location",$redir);
    # warn "redir[$redir]";
    return $res->finalize;
  }
  return unless $uri eq "$location/";

  # CASE 2

  # warn sprintf "uri[%s]location[%s]path_info[%s]", $uri, $location, $r->path_info;
  $req->path("$location/query");
  $req->path_info("") if $req->path_info;
  return;
}

1;

#Local Variables:
#mode: cperl
#cperl-indent-level: 2
#End:
