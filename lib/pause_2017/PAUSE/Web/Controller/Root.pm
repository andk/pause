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
  my $u = $c->active_user_record;

  # Special case for cpan-uploaders that post to the /pause/authenquery without any ACTION
  return unless $u->{userid};
  return unless uc $req->method eq 'POST';
  return unless $req->param('SUBMIT_pause99_add_uri_HTTPUPLOAD' || $req->param('SUBMIT_pause99_add_uri_httpupload');

  my $action = 'add_uri';
  $req->param('ACTION' => $action);
  $pause->{Action} = $action;
  return $c->delegate($action);
}

sub auth {
  my $c = shift;
  return 1;
}

1;
