package pause_1999::index;
use strict;
use Apache::Constants qw(:common);
our $VERSION = "304";

sub handler {
  my $r = shift or return DECLINED;
  if ($r->is_initial_req) {
    my $the_request = $r->the_request;
    my $redir_to;
    my $server = $r->server->server_hostname;
    my $port = $r->server->port || 80;
    my $scheme = $port == 443 ? "https" : "http";
    my $is_ssl = $r->header_in("X-pause-is-SSL") || 0;
    if ($is_ssl) {
        $scheme = "https";
    }
    if ($the_request =~ m|^GET /\?|) {
      my $args = $r->args;
      # warn "Returning SERVER_ERROR: the_request[$the_request]uri[$uri]args[$args]";
      # return SERVER_ERROR;
      my $uri = "/pause/query";
      $args =~ s|/$||;
      $args =~ s|\s.*||;
      $args = "?$args" if $args;
      $redir_to = "$scheme\://$server$uri$args";
      # warn "Statistics: Redirecting the_request[$the_request]redir_to[$redir_to]";
      $r->header_out("Location",$redir_to);
      my $stat = Apache::Constants::REDIRECT();
      # $r->status($stat);
      # $r->send_http_header;
      return $stat;
    }
    my $uri = $r->uri;
    #my $host = $r->server->server_hostname;
    #my $args = $r->args;
    #warn "index-uri[$uri]host[$host]args[$args]";
    return DECLINED unless $uri eq "/" || $uri eq "/index.html";
    my(%redir) = (
                  "/" => "query",
                  "/index.html" => "query?ACTION=pause_news",
                 );
    # $r->internal_redirect_handler("/query");
    $redir_to = sprintf "%s://%s/pause/%s", $scheme, $server, $redir{$uri};
    $r->header_out("Location",$redir_to);
    my $stat = Apache::Constants::REDIRECT();
    return $stat;
  } else {
    return OK;
  }
}

1;

