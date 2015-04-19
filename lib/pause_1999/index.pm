package pause_1999::index;
use strict;
use HTTP::Status qw(:constants);
our $VERSION = "304";

sub handler {
  my $req = shift;
  if (1) { # $r->is_initial_req
    my $method = $req->method;
    my $redir_to = $req->base;
    my $is_ssl = $req->header("X-pause-is-SSL") || 0;
    if ($is_ssl) {
        $redir_to->scheme("https");
    }
    if ($method eq 'GET' && $redir_to->path eq '/' && $req->env->{QUERY_STRING}) {
      my $args = $req->env->{QUERY_STRING};
      # warn "Returning SERVER_ERROR: the_request[$the_request]uri[$uri]args[$args]";
      # return SERVER_ERROR;
      $redir_to->path("/pause/query");
      $args =~ s|/$||;
      $args =~ s|\s.*||;
      $redir_to->query($args) if $args;
      # warn "Statistics: Redirecting the_request[$the_request]redir_to[$redir_to]";
      my $res = $req->new_response(HTTP_MOVED_PERMANENTLY);
      $res->header("Location",$redir_to);
      return $res->finalize;
    }
    my $uri = $req->path;
    #my $host = $r->server->server_hostname;
    #my $args = $r->args;
    #warn "index-uri[$uri]host[$host]args[$args]";
    return HTTP_NOT_FOUND unless $uri eq "/" || $uri eq "/index.html";
    #my(%redir) = (
    #              "/" => "query",
    #              "/index.html" => "query?ACTION=pause_05news",
    #             );
    # $r->internal_redirect_handler("/query");
    $redir_to->path("/pause/query");
    $redir_to->query("ACTION=pause_05news") if $uri eq "/index.html";
    my $res = $req->new_response(HTTP_MOVED_PERMANENTLY);
    $res->header("Location",$redir_to);
    return $res->finalize;
#  } else {
#    return OK;
  }
}

1;

