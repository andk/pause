package PAUSE::Web::Plugin::RenderYAML;

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
    my $action = $c->req->param('ACTION') || 'pause';
    $c->res->headers->content_disposition("attachment; filename=$action.yaml");
    $c->res->headers->content_type('application/yaml');
    $c->stash(format => "text");
    $c->render(text => $edump);
    return;
  });
}

1;
