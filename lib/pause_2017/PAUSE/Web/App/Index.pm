package PAUSE::Web::App::Index;

use Mojo::Base -base;
use Plack::Request;
use Plack::Response;
use HTTP::Status qw/:constants/;

sub to_app {
  my $self = shift;

  return sub {
    my $req = Plack::Request->new(shift);
    my $res = $self->dispatch($req);
    return $res if ref $res;
    [$res =~ /^\d+$/ ? $res : 500, [], [$res]];
  };
}


sub dispatch {
  my ($self, $req) = @_;

  my $method = $req->method;
  my $redir_to = $req->base;
  my $is_ssl = $req->headers->header("X-pause-is-SSL") || 1;
  if ($is_ssl) {
    $redir_to->scheme("https");
  }
  if ($method eq "GET" && $redir_to->path eq "/" && $req->env->{QUERY_STRING}) {
    my $args = $req->env->{QUERY_STRING};
    # warn "Returning SERVER_ERROR: the_request[$the_request]uri[$uri]args[$args]";
    # return SERVER_ERROR;
    $redir_to->path("/pause/query");
    $args =~ s|/$||;
    $args =~ s|\s.*||;
    $redir_to->query($args) if $args;
    # warn "Statistics: Redirecting the_request[$the_request]redir_to[$redir_to]";
    my $res = $req->new_response(HTTP_MOVED_PERMANENTLY);
    $res->headers->header("Location", $redir_to);
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
  $res->headers->header("Location", $redir_to);
  return $res->finalize;
}

1;
