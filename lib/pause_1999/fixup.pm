#!/usr/bin/perl -- -*- Mode: cperl; -*-
package pause_1999::fixup;
use strict;
use Apache::Constants qw(:common);
our $VERSION = sprintf "%d", q$Rev$ =~ /(\d+)/;

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
  my $r = shift or return DECLINED;
  return OK unless $r->is_initial_req;
  my $uri = $r->uri;
  my $location = $r->location;

  # CASE 3

  return DECLINED if $location =~ /query/;

  # warn "uri[$uri]location[$location] (Question was, does location ever match /query/?)";
  if ($uri eq $location) {

    # CASE 1

    my $proto = $r->server->port == 443 ? "https" : "http";
    my $server = $r->server->server_hostname;
    my $redir = "$proto://$server$location/query";
    $r->header_out("Location",$redir);
    # warn "redir[$redir]";
    $r->status(Apache::Constants::MOVED());
    $r->send_http_header;
    return Apache::Constants::MOVED();
  }
  return DECLINED unless $uri eq "$location/";

  # CASE 2

  # warn sprintf "uri[%s]location[%s]path_info[%s]", $uri, $location, $r->path_info;
  $r->uri("$location/query");
  $r->path_info("") if $r->path_info;
  $r->handler("perl-script");
  require pause_1999::config;
  $r->set_handlers("PerlHandler",[qw(pause_1999::config)]);
  OK;
}

1;
