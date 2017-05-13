package PAUSE::Web::Plugin::Delegate;

# Mojolicious doesn't have this feature with good intention
# but we need this anyway

use Mojo::Base "Mojolicious::Plugin";

sub register {
  my ($self, $app, $conf) = @_;
  $app->helper(delegate => \&_delegate);
}

sub _delegate {
  my ($c, $action) = @_;
  my $routes = $c->app->routes;
  my $route = $routes->lookup($action) or die "no route for $action";
  my $to = $route->to;
  push @{$c->match->stack}, $to;
  $routes->_controller($c, $to);
  return;
}

1;
