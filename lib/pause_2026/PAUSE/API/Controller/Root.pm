package PAUSE::API::Controller::Root;

use Mojo::Base "Mojolicious::Controller";
use HTTP::Date ();
use Time::Duration ();
use PAUSE;

sub check {
  my $c = shift;

  if (my $res = _pause_is_closed()) {
    $c->render(json => $res, status => 503);
    return;
  }

  return 1;
}

sub _pause_is_closed {
  my $dti = PAUSE::downtimeinfo();
  my $downtime = $dti->{downtime};
  my $willlast = $dti->{willlast};

  # TODO: just ignore scheduled downtime for now
  if (time >= $downtime && time < $downtime + $willlast) {
    my $delta = $downtime + $willlast - time;
    my $expr = Time::Duration::duration($delta);
    my $willlast_dur = Time::Duration::duration($willlast);
    return {
      closed => {
        delta => $expr,
        will_last => $willlast_dur,
      }
    };
  }
  return;
}

1;
