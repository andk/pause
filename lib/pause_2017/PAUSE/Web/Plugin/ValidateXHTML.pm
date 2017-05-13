package PAUSE::Web::Plugin::ValidateXHTML;

use Mojo::Base "Mojolicious::Plugin";
use XML::Parser;
use String::Random;

sub register {
  my ($self, $app, $conf) = @_;
  $app->hook(after_render => \&_validate);
}

sub _validate {
  my ($c, $output, $format) = @_;
  return unless $format eq "html";
  # FIXME: my $parser = XML::Parser->new;
  my $parser = XML::Parser->new(ErrorContext => 5);
  eval { $parser->parse("$$output") };
  if ($@) {
    my $rand = String::Random::random_string("cn");
    warn "XML::Parser error. rand[$rand]\$\@[$@]";
    my $deadmeat = $c->app->home->rel_file("tmp/deadmeat/$rand.xhtml");
    # FIXME: my $deadmeat = "/var/run/httpd/deadmeat/$rand.xhtml";
    if (open my $fh, ">", $deadmeat) {
      binmode $fh, ":utf8";
      $fh->print($$output);
      $fh->close;
    } else {
      warn "Couldn't open >$deadmeat: $!";
    }
  }
  return 1;
}

1;
