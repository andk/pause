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
}

sub auth {
  my $c = shift;
  return 1;
}

1;
