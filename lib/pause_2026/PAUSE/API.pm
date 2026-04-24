package PAUSE::API;

use Mojo::Base "Mojolicious";
use MojoX::Log::Dispatch::Simple;
use HTTP::Status qw/:constants status_message/;
use JSON;

has pause => sub { Carp::confess "requires PAUSE::API::Context" };

sub startup {
  my $app = shift;

  $app->moniker("pause-api");

  $app->max_request_size(0); # indefinite upload size

  # Set the same logger as the one Plack uses
  # (initialized in app.psgi)
  $app->log(MojoX::Log::Dispatch::Simple->new(
    dispatch => $app->pause->logger,
    level => "debug",
  ));

  $app->hook(around_dispatch => \&_log);
  $app->hook(around_dispatch => \&_wrap);

  # Set random secrets to keep mojo session secure
  $app->secrets($app->pause->secrets);

  $app->routes->namespaces($app->pause->controller_namespaces);

  # Check HTTP headers and set stash
  my $r = $app->routes->under("/")->to("root#check", format => 'json');

  my $requires_token = $r->under("/")->to("root#check_token", format => 'json');

  $requires_token->post("/upload")->to("upload#upload", format => 'json');
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

sub _wrap {
  my ($next, $c, $action, $last) = @_;

  my $pause = $c->stash(".pause");
  if (!$pause) {
    $pause = {};
    $c->stash(".pause", $pause);
  }

  my $res = eval { $next->(); };
  if (my $e = $@) {
    if (UNIVERSAL::isa($e, "PAUSE::Web::Exception")) {
      if ($e->{ERROR}) {
        $e->{ERROR} = [ $e->{ERROR} ] unless ref $e->{ERROR} eq 'ARRAY';
        push @{$pause->{ERROR}}, map { s/\s\s+/ /sgr } @{$e->{ERROR}};
        require Data::Dumper;
        my $message = "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . Data::Dumper->new([$pause->{ERROR}],[qw(error)])->Indent(1)->Useqq(1)->
Dump;
        $c->app->pause->log({level => 'debug', message => $message});
        $c->res->code($e->{HTTP_STATUS} // HTTP_BAD_REQUEST);
        return $c->render(json => { error => $pause->{ERROR} })
      } elsif ($e->{HTTP_STATUS}) {
        return $c->render(json => {error => status_message($e->{HTTP_STATUS})});
      }
    } else {
      # this is NOT a known error type, we need to handle it anon
      my $error = "$e";
      $c->app->pause->log({level => 'error', message => $error });
      $c->res->code(HTTP_INTERNAL_SERVER_ERROR);
      return $c->render(json => {error => 'Internal server error'});
    }
  }
  return $res;
}

1;
