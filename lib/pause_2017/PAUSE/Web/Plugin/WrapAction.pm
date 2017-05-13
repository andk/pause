package PAUSE::Web::Plugin::WrapAction;

use Mojo::Base "Mojolicious::Plugin";
use HTTP::Status qw/:constants/;

sub register {
  my ($self, $app, $conf) = @_;

  $app->hook(around_action => \&_wrap);
}

sub _wrap {
  my ($next, $c, $action, $last) = @_;

  my $pause = $c->stash(".pause");

  my $res = eval { $next->(); };
  if ($@) {
    if (UNIVERSAL::isa($@, "PAUSE::Web::Exception")) {
      if ($@->{ERROR}) {
        $@->{ERROR} = [ $@->{ERROR} ] unless ref $@->{ERROR};
        push @{$pause->{ERROR}}, @{$@->{ERROR}};
        require Data::Dumper;
        print STDERR "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . Data::Dumper->new([$pause->{ERROR}],[qw(error)])->Indent(1)->Useqq(1)->Dump; # XXX
      } elsif ($@->{HTTP_STATUS}) {
        $c->res->code($@->{HTTP_STATUS});
        return;
      }
    } else {
      # this is NOT a known error type, we need to handle it anon
      my $error = "$@";
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
