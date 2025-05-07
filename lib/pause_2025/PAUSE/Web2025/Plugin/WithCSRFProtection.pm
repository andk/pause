package PAUSE::Web2025::Plugin::WithCSRFProtection;

# patched version of Mojolicious::Plugin::WithCSRFProtection
# cf. https://github.com/charsbar/Mojolicious-Plugin-WithCSRFProtection/pull/2

# ABSTRACT: Mojolicious plugin providing CSRF protection at the routing level

use Mojo::Base 'Mojolicious::Plugin';

our $VERSION = '1.00_01';

sub register {
    my ( $self, $app ) = @_;

    my $routes = $app->routes;

    $app->helper(
        'reply.bad_csrf' => sub {
            my ($c) = @_;
            $c->res->code(403);
            $c->render_maybe('bad_csrf')
                or $c->render( text => 'Failed CSRF check' );
            return;
        }
    );

    $routes->add_condition(
        with_csrf_protection => sub {
            my ( $route, $c ) = @_;

            my $csrf = $c->req->headers->header('X-CSRF-Token')
                || $c->param('csrf_token');

            unless ( $csrf && $csrf eq $c->csrf_token ) {
                $c->reply->bad_csrf unless $c->stash->{'mojo.finished'};
                return;
            }

            return 1;
        }
    );

    $routes->add_shortcut(
        with_csrf_protection => sub {
            my ($route) = @_;
            return $route->requires( with_csrf_protection => 1 );
        }
    );

    return;
}

1;

__END__

=head1 SYNOPSIS

   # in a lite application
   post '/some-url' => ( with_csrf_protection => 1 ) => sub { ... };

   # in a full application
   $app->routes->post('/some-url')
               ->with_csrf_protection
               ->to(...);

=head1 DESCRIPTION

This Mojolicious plugin provides a routing condition (called
C<with_csrf_protection>) and routing shortcut to add that condition (also called
C<with_csrf_protection>) that can be used to protect against cross site request
forgery.

Adding the condition to the route checks a valid CSRF token was passed, either
in the C<X-CSRF-Token> HTTP header or in the C<crsf_token> parameter.

Failing the CSRF check causes a 403 error and the C<bad_csrf> template to be
rendered, or if no such template is found a simple error string to be
output. This behavior is unlike most conditions that can be applied to
Mojolicious routes that normally just cause the route matching to fail and
alternative subsequent routes to be evaluated, but immediately returning an
error response makes sense for a failed CSRF check.  The actual error rendering
is performed by the C<reply.bad_csrf> helper that this plugin installs, and if
you want different error output you should override that helper.

=head1 EXAMPLES

=head2 A Mojolicious::Lite application

Here's a simple Mojolicious application that I can run on my desktop computer
that creates a very simple web interface to adding things to do to my
C<todo.txt>.

Because I don't want anyone web page on the internet to be able to tell my
browser to add whatever that web page feels like to my todo list, I add CSRF
protection with the C<< with_csrf_protection => 1 >> condition to the POST.

  #!/usr/bin/perl

  use Mojolicious::Lite;

  plugin 'WithCSRFProtection';
  plugin 'TagHelpers';

  get '/' => sub {} => 'index';

  post '/note' => (with_csrf_protection => 1) => sub {
      my ($c) = @_;
      open my $fh, '>>', $ENV{HOME}.'/todo.txt' or die "Can't open todo: $!";
      print $fh $c->param('item'), "\n";
  };

  app->start;

  __DATA__
  @@ index.html.ep
  <html>
  <body>
  %= form_for note => begin
      %= text_field 'item'
      %= csrf_field
      %= submit_button
  % end
  </body>
  </html>

  @@ note.html.ep
  <html>
  <body>
  Okay, I wrote that down!
  </body>
  </html>

The template for the index makes use of the C<csrf_field> tag helper to
render a hidden input field containing the current csrf_token:

  <html>
  <body>
  <form action="/note" method="POST">
    <input name="item" type="text">
    <input name="csrf_token" type="hidden" value="428d33ed67f886dd1a2c1a3c493708f5158bf77d">
    <input type="submit" value="Ok">
  </form></body>
  </html>

However if a bad agent causes your browser to try POSTing to the form without
the CSRF token (or for that matter the corresponding session cookie), you just
get the standard CSRF protection error message:

   shell$ curl -X POST -F 'item=transfer money to bad guys' http://127.0.0.1:3000/note
   Failed CSRF check

=head2 A Mojolicious AJAX application

In this example we have a hypothetical Mojolicious application that uses jQuery
to POST some JSON to the server.  To provide CSRF protection we make use of the
C<X-CSRF-Token> header.

It's possible to configure jQuery to add additional headers on each request:

   <script>
      $.ajaxSetup({ headers:
   %  use Mojo::JSON qw( to_json );
   %= to_json({ 'X-CSRF-Token' => $c->crsf_token })
      });
   </script>

Once you've done this it's further possible wherever you define your routes to
require this CSRF header (or one of the C<csrf_token> parameters) with the
C<with_csrf_protection> shortcut (which just applies the C<with_csrf_protection>
condition)

 sub startup {
   my ($self) = @_;
   $self->routes
        ->post('/launch-nukes')
        ->with_csrf_protection
        ->to('nuke#launch');
   ...
 }
