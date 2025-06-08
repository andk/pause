package PAUSE::Web2025::Plugin::SessionCounted;

use Mojo::Base "Mojolicious::Plugin";
use Mojo::File;
use Apache::Session::Counted;
use PAUSE ();

our $SessionDataDir = "$PAUSE::Config->{RUNDATA}/session/sdata";
our $SessionCounterDir = "$PAUSE::Config->{RUNDATA}/session/cnt";

sub register {
  my ($self, $app, $conf) = @_;

  Mojo::File->new($SessionDataDir)->make_path;
  Mojo::File->new($SessionCounterDir)->make_path;

  Apache::Session::CountedStore->tree_init($SessionDataDir, 1);

  $app->helper(session_data_dir => sub { $SessionDataDir });
  $app->helper(session_counted => \&_session);
  $app->helper(new_session_counted => \&_new_session);
  $app->helper(session_counted_userid => \&_userid);
}

sub _session {
  my $c = shift;
  my $stash = $c->stash(".pause.session") or return;
  $stash->{session};
}

sub _new_session {
  my $c = shift;
  my $stash = $c->stash(".pause.session");
  $c->stash(".pause.session" => $stash = {}) unless $stash;

  my $mgr = $c->app->pause;
  my $sid = $c->req->param('USERID'); # may fail
  my %session;
  # XXX date string into CounterFile!
  tie %session, 'Apache::Session::Counted',
      $sid, {
             Directory => $SessionDataDir,
             DirLevels => 1,
             CounterFile => _session_counter_file(),
            };
  $stash->{session} = \%session;
}

sub _session_counter_file {
  my(@time) = gmtime; # sec,min,hour,day,month,year
  my $quartal = int($time[4]/3) + 1; # 1..4
  "$SessionCounterDir/Q$quartal";
}

sub _userid {
  my $c = shift;
  my $stash = $c->stash(".pause.session");

  # I'm working for the first time with Apache::Session::Counted
  # Things have changed a bit. Until today we had no userid until we
  # had dumped the current request. With Apache::Session we have a
  # userid from the moment we open a session. Under many circumstances
  # we do not need a session, so we do not need a userid. We typically
  # need a userid either to retrieve an old value or to store a new
  # value. We know that we have to retrieve an old value if there is a
  # USERID=xxx parameter on the request. We know that we want to store
  # something if we call ->userid.

  # Apache::Session will dump the current request even if we do not
  # need it. That's stupid. Cookie based session concepts are
  # careless. But let's delay this discussion and see if our code
  # works first.

  return $stash->{userid} if defined $stash->{userid};
  # we must find out if there is an old request that needs to be
  # restored because if there is, we must not create a new one.
  # Because if we create a new one, the restorer cannot restore it
  # without clobbering _session_id

  # Talking about session: lets delegate the problem to the session

  my $session = $c->session_counted;
  $stash->{userid} = $session->{_session_id};
  $session->{_session_id} = $stash->{userid};# funny, isn't it? We
                                             # trigger a STORE here
                                             # which triggers a
                                             # MODIFIED so that the
                                             # DESTROY will actually
                                             # save the hash
}

1;
