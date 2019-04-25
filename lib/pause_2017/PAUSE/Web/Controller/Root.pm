package PAUSE::Web::Controller::Root;

use Mojo::Base "Mojolicious::Controller";

sub check {
  my $c = shift;

  if ($c->pause_is_closed) {
    my $user = $c->req->env->{REMOTE_USER};
    if ($user and $user eq "ANDK") {
    } else {
      $c->render("closed");
      return;
    }
  }

  return 1;
}

sub index {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  return unless exists $pause->{User};
  my $u = $c->active_user_record;

  # Special case for cpan-uploaders that post to the /pause/authenquery without any ACTION
  return unless $u->{userid};
  return unless uc $req->method eq 'POST';
  return unless $req->param('SUBMIT_pause99_add_uri_HTTPUPLOAD') || $req->param('SUBMIT_pause99_add_uri_httpupload');

  my $action = 'add_uri';
  $req->param('ACTION' => $action);
  $pause->{Action} = $action;

  # kind of delegate but don't add action to stack
  my $routes = $c->app->routes;
  my $route = $routes->lookup($action) or die "no route for $action";
  my $to = $route->to;
  $routes->_controller($c, $to);
}

sub auth {
  my $c = shift;
  return 1;
}

1;
