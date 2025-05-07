package PAUSE::Web2025::Plugin::IsPauseClosed;

use Mojo::Base "Mojolicious::Plugin";
use HTTP::Date ();
use Time::Duration ();

sub register {
  my ($self, $app, $conf) = @_;

  $app->helper(pause_is_closed => \&_check);
}

sub _check {
  my $c = shift;
  my $dti = PAUSE::downtimeinfo();
  my $downtime = $dti->{downtime};
  my $willlast = $dti->{willlast};
  my $pause = $c->stash(".pause");

  if (time < $downtime) {
    my $httptime = HTTP::Date::time2str($downtime);
    my $delta = $downtime - time;
    my $expr = Time::Duration::duration($delta);
    my $willlast_dur = Time::Duration::duration($willlast);
    $pause->{scheduled_downtime} = {
      httptime => $httptime,
      delta => $expr,
      will_last => $willlast_dur,
    };
  } elsif (time >= $downtime && time < $downtime + $willlast) {
    my $delta = $downtime + $willlast - time;
    my $expr = Time::Duration::duration($delta);
    my $willlast_dur = Time::Duration::duration($willlast);
    $pause->{closed} = {
      delta => $expr,
      will_last => $willlast_dur,
    };
  }
}

1;
