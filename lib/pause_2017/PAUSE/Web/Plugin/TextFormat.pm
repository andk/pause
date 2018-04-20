package PAUSE::Web::Plugin::TextFormat;

use Mojo::Base "Mojolicious::Plugin";
use Mojo::ByteStream;
use Text::Format;

sub register {
  my ($self, $app, $conf) = @_;
  $app->helper(text_format => \&_text_format);
}

sub _wrap {
  my ($c, $block) = @_;
  my $result = $block->();
  Mojo::ByteStream->new(Text::Format->new(firstIndent => 0)->format($result));
}

1;
