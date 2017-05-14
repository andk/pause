package PAUSE::Web;

use Mojo::Base "Mojolicious";
use MojoX::Log::Dispatch::Simple;
use Digest::SHA1 qw/sha1_hex/;

has pause => sub { Carp::confess "requires PAUSE::Web::Context" };

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

  # Set random secrets to keep mojo session secure
  $app->secrets([sha1_hex($$.time)]);

  # Fix template path for now
  unshift @{$app->renderer->paths}, $app->home->rel_file("lib/pause_2017/templates");

  # Fix static path
  unshift @{$app->static->paths}, $app->home->rel_file("htdocs");

  # Load plugins to modify path/set stash values/provide helper methods
  $app->plugin("WithCSRFProtection");
  $app->plugin("PAUSE::Web::Plugin::ConfigPerRequest");
  $app->plugin("PAUSE::Web::Plugin::IsPauseClosed");
  $app->plugin("PAUSE::Web::Plugin::GetActiveUserRecord");
  $app->plugin("PAUSE::Web::Plugin::GetUserMeta");
  $app->plugin("PAUSE::Web::Plugin::ServePauseDoc");
  $app->plugin("PAUSE::Web::Plugin::FixAction");
  $app->plugin("PAUSE::Web::Plugin::WrapAction");
  $app->plugin("PAUSE::Web::Plugin::EditUtils");
  $app->plugin("PAUSE::Web::Plugin::Delegate");
  $app->plugin("PAUSE::Web::Plugin::SessionCounted");
  $app->plugin("PAUSE::Web::Plugin::MyURL");
  $app->plugin("PAUSE::Web::Plugin::RenderYAML");
  $app->plugin("PAUSE::Web::Plugin::TextFormat");
  $app->plugin("PAUSE::Web::Plugin::ValidateXHTML");

  # tweak default TagHelpers to spit xml for now
  {
    no warnings 'redefine';
    *Mojolicious::Plugin::TagHelpers::_tag = \&_fix_tag;
  }

  # Check HTTP headers and set stash
  my $r = $app->routes->under("/")->to("root#check");

  # Public Menu
  my $public = $r->under("/query");
  $public->any("/")->to("root#index");
  for my $group ($app->pause->config->public_groups) {
    for my $name ($app->pause->config->action_names_for($group)) {
      $public->any("/$name")->to($app->pause->config->action($name)->{x_mojo_to});
    }
  }

  # Private/User Menu
  my $private = $r->under("/authenquery")->to("root#auth");
  $private->any("/")->to("root#index");
  for my $group ($app->pause->config->all_groups) {
    for my $name ($app->pause->config->action_names_for($group)) {
      $private->any("/$name")->to($app->pause->config->action($name)->{x_mojo_to});
    }
  }
}

sub _fix_tag {
  my $tree = ['tag', shift, undef, undef];

  # Content
  if (ref $_[-1] eq 'CODE') { push @$tree, ['raw', pop->()] }
  elsif (@_ % 2) { push @$tree, ['text', pop] }

  # Attributes
  my $attrs = $tree->[2] = {@_};
  if (ref $attrs->{data} eq 'HASH' && (my $data = delete $attrs->{data})) {
    @$attrs{map { y/_/-/; lc "data-$_" } keys %$data} = values %$data;
  }
  return Mojo::ByteStream->new(Mojo::DOM::HTML::_render($tree, 'xml')); # TWEAKED
}

1;
