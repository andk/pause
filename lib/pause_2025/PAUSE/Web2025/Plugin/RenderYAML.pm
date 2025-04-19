package PAUSE::Web2025::Plugin::RenderYAML;

use Mojo::Base "Mojolicious::Plugin";
use YAML::Syck;
use Encode;

sub register {
  my ($self, $app, $conf) = @_;

  $app->helper(render_yaml => sub {
    my ($c, $data) = @_;
    local $YAML::Syck::ImplicitUnicode = 1;
    my $dump = YAML::Syck::Dump($data);
    my $edump = Encode::encode_utf8($dump);
    $c->stash(format => "text");
    $c->render(text => $edump);
    return;
  });
}

1;
