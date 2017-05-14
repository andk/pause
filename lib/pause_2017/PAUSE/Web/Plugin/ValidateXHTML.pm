package PAUSE::Web::Plugin::ValidateXHTML;

use Mojo::Base "Mojolicious::Plugin";
use XML::Parser;
use String::Random;

sub register {
  my ($self, $app, $conf) = @_;
  $app->hook(after_render => \&_validate);

  # tweak default TagHelpers to spit xml, and Parameters recognize ";" for now
  {
    no warnings 'redefine';
    *Mojolicious::Plugin::TagHelpers::_tag = \&_fix_tag;
  }
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
