package PAUSE::Web2025::Plugin::WrapAction;

use Mojo::Base "Mojolicious::Plugin";
use HTTP::Status qw/:constants status_message/;

sub register {
  my ($self, $app, $conf) = @_;

  $app->hook(around_dispatch => \&_wrap);
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
    if (UNIVERSAL::isa($e, "PAUSE::Web2025::Exception")) {
      if ($e->{NEEDS_LOGIN}) {
        $c->redirect_to('/login');
        return;
      }
      elsif ($e->{ERROR}) {
        $e->{ERROR} = [ $e->{ERROR} ] unless ref $e->{ERROR} eq 'ARRAY';
        push @{$pause->{ERROR}}, @{$e->{ERROR}};
        require Data::Dumper;
        my $message = "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . Data::Dumper->new([$pause->{ERROR}],[qw(error)])->Indent(1)->Useqq(1)->Dump;
        $c->app->pause->log({level => 'debug', message => $message});
        $c->res->code($e->{HTTP_STATUS}) if $e->{HTTP_STATUS};
        $c->render('layouts/layout') unless $c->stash('Action');
      } elsif ($e->{HTTP_STATUS}) {
        $c->res->headers->content_type('text/plain');
        $c->res->body(status_message($e->{HTTP_STATUS}));
        $c->rendered($e->{HTTP_STATUS});
        return;
      }
    } else {
      # this is NOT a known error type, we need to handle it anon
      my $error = "$e";
      if ($pause->{ERRORS_TO_BROWSER}) {
        push @{$pause->{ERROR}}, " ", $error;
      } else {
        $c->app->pause->log({level => 'error', message => $error });
        $c->res->code(HTTP_INTERNAL_SERVER_ERROR);
        $c->reply->exception($error);
        return;
      }
    }
  }
  return $res;
}

1;
