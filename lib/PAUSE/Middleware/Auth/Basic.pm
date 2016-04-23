package PAUSE::Middleware::Auth::Basic;
use strict;
use parent qw(Plack::Middleware::Auth::Basic);
use Plack::Request;
use HTTP::Status qw(:constants);
use pause_1999::authen_user;

sub prepare_app { shift->realm('PAUSE') }

sub call {
    my($self, $env) = @_;

    my $auth = $env->{HTTP_AUTHORIZATION}
        or return $self->unauthorized;

    my $req = Plack::Request->new($env);
    my $res = pause_1999::authen_user::handler($req);

    return $res->finalize if ref $res;
    return $self->unauthorized unless $res == HTTP_OK;
    return $self->app->($env);
}

1;
