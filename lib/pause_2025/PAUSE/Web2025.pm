package PAUSE::Web2025;

use Mojo::Base "Mojolicious";
use MojoX::Log::Dispatch::Simple;
use Digest::SHA1 qw/sha1_hex/;

has pause => sub { Carp::confess "requires PAUSE::Web2025::Context" };

sub startup {
  my $app = shift;

  $app->moniker("pause-web");

  $app->max_request_size(0); # indefinite upload size

  # Set the same logger as the one Plack uses
  # (initialized in app.psgi)
  $app->log(MojoX::Log::Dispatch::Simple->new(
    dispatch => $app->pause->logger,
    level => "debug",
  ));

  $app->hook(around_dispatch => \&_log);

  # Set random secrets to keep mojo session secure
  $app->secrets([sha1_hex($app->pause->secret)]);

  # Fix template path for now
  unshift @{$app->renderer->paths}, $app->home->rel_file("lib/pause_2025/templates");

  # Fix static path
  unshift @{$app->static->paths}, $app->home->rel_file("htdocs");

  # Load plugins to modify path/set stash values/provide helper methods
  $app->plugin("WithCSRFProtection");
  $app->plugin("PAUSE::Web2025::Plugin::ConfigPerRequest");
  $app->plugin("PAUSE::Web2025::Plugin::IsPauseClosed");
  $app->plugin("PAUSE::Web2025::Plugin::GetActiveUserRecord");
  $app->plugin("PAUSE::Web2025::Plugin::GetUserMeta");
  $app->plugin("PAUSE::Web2025::Plugin::ServePauseDoc");
  $app->plugin("PAUSE::Web2025::Plugin::WrapAction");
  $app->plugin("PAUSE::Web2025::Plugin::EditUtils");
  $app->plugin("PAUSE::Web2025::Plugin::Delegate");
  $app->plugin("PAUSE::Web2025::Plugin::SessionCounted");
  $app->plugin("PAUSE::Web2025::Plugin::MyURL");
  $app->plugin("PAUSE::Web2025::Plugin::RenderYAML");
  $app->plugin("PAUSE::Web2025::Plugin::TextFormat");
  $app->plugin("PAUSE::Web2025::Plugin::UserRegistration");

  # Check HTTP headers and set stash
  my $r = $app->routes->under("/")->to("root#check");

  # Public Menu
  my $public = $r->under("/")->to("root#public");
  $public->any("/")->to("root#index");
  for my $group ($app->pause->config->public_groups) {
    for my $name ($app->pause->config->action_names_for($group)) {
      my $action = $app->pause->config->action($name);
      for my $method (qw/get post/) {
        my $route = $public->$method("/$group/$name");
        $route->with_csrf_protection if $method eq "post" and $action->{x_csrf_protection};
        $route->to($action->{x_mojo_to}, ACTION => $name)->name($name);
      }
    }
  }
  # change_passwd is public when it is used for password recovery
  my $action = $app->pause->config->action('change_passwd');
  for my $method (qw/get post/) {
    my $route = $public->$method("/public/change_passwd");
    $route->with_csrf_protection if $method eq "post" and $action->{x_csrf_protection};
    $route->to($action->{x_mojo_to}, ACTION => 'change_passwd')->name('change_passwd');
  }

  # login
  for my $method (qw/get post/) {
    my $route = $public->$method("/login");
    $route->with_csrf_protection if $method eq "post" and $action->{x_csrf_protection};
    $route->to("root#login", ACTION => 'login');
  }

  # Private/User Menu
  my $private = $r->under("/")->to("root#auth");
  $private->any("/")->to("root#index");
  for my $group ($app->pause->config->all_groups) {
    for my $name ($app->pause->config->action_names_for($group)) {
      my $action = $app->pause->config->action($name);
      for my $method (qw/get post/) {
        my $route = $private->$method("/$group/$name");
        $route->with_csrf_protection if $method eq "post" and $action->{x_csrf_protection};
        $route->to($action->{x_mojo_to}, ACTION => $name)->name($name);
      }
    }
  }
}

sub _log {
  my ($next, $c) = @_;
  local $SIG{__WARN__} = sub {
    my $message = shift;
    chomp $message;
    Log::Dispatch::Config->instance->log(
      level => 'warn',
      message => $message,
    );
  };
  $c->helpers->reply->exception($@) unless eval { $next->(); 1 };
}

1;
