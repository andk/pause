package PAUSE::Web::Plugin::FixAction;

use Mojo::Base "Mojolicious::Plugin";
use HTTP::Status qw/:constants/;

# Set hook to convert old ACTION params to router paths
sub register {
  my ($self, $app, $conf) = @_;

  $app->hook(before_dispatch => \&_fix);
}

sub _fix {
  my $c = shift;

  #_fixup($c); # does what fixup handler did

  my $action = $c->req->param("ACTION");

  # Ignore if there's no ACTION or ACTION overrides root
  return if !$action or $action eq "root";
  my $path = $c->req->url->path;
  $c->req->url->path("$path/$action");
  $c->stash(".pause")->{Action} = $action;
}

# pause_1999::fixup::handler

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

sub _fixup {
  my $c = shift;
  my $req = $c->req;

  my $uri = $req->request_uri;
  my $location = '/pause'; # $r->location;

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
