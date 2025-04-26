package PAUSE::Web2025::Plugin::MyURL;

use Mojo::Base "Mojolicious::Plugin";
use Mojo::URL;

sub register {
  my ($self, $app, $conf) = @_;

  # Because we tweak url to pass ACTION param to path,
  # we can't use default "url_for" that uses the tweaked path
  # to generate a url
  $app->helper(my_url => sub {
    my $c = shift;
    my %param = ref $_[0] ? () : @_;
    my $action = $c->stash('.pause')->{Action};
    my $requested_action = $param{ACTION} ? delete $param{ACTION} : '';
    my $url = $c->url_for($action && $action ne $requested_action ? $action : $requested_action);
    $url->query(ref $_[0] ? $_[0] : %param);
    $url->query->remove('ABRA');
    $url;
  });
  $app->helper(my_full_url => sub {
    my $c = shift;
    my $url = Mojo::URL->new($c->req->env->{REQUEST_URI})->base($c->req->url->to_abs->base)->to_abs;
    $url->query->remove('ABRA');
    $url;
  });
}

1;
