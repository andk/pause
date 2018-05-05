package PAUSE::Web::Plugin::MyURL;

use Mojo::Base "Mojolicious::Plugin";
use Mojo::URL;

sub register {
  my ($self, $app, $conf) = @_;

  # Because we tweak url to pass ACTION param to path,
  # we can't use default "url_for" that uses the tweaked path
  # to generate a url
  $app->helper(my_url => sub {
    my $c = shift;
    my $url = Mojo::URL->new($c->req->env->{REQUEST_URI});
    my $action = $c->stash('.pause')->{Action};
    my $requested_action = $url->query->param('ACTION') // '';
    $url->query->param(ACTION => $action) if $action && $action ne $requested_action;
    $url;
  });
  $app->helper(my_full_url => sub {
    my $c = shift;
    Mojo::URL->new($c->req->env->{REQUEST_URI})->base($c->req->url->to_abs->base)->to_abs;
  });
}

1;
