package PAUSE::Web::Plugin::ServePauseDoc;

use Mojo::Base "Mojolicious::Plugin";
use PAUSE::Web::Util::RewriteXHTML;
use Encode;

sub register {
  my ($self, $app, $conf) = @_;
  $app->helper(serve_pause_doc => \&_serve_pause_doc);
}

# pause_1999::edit::show_document
sub _serve_pause_doc {
  my ($c, $name, $rewrite) = @_;

  my $home = $c->app->home;

  my $html;
  for my $subdir ("htdocs", "pause", "pause/../htdocs", "pause/..", ".") {
    my $file = $home->rel_file("$subdir/$name");
    next unless -f $file;
    $html = decode_utf8($file->slurp);
    last;
  }

  if ($rewrite and !ref $rewrite) {
    $html = PAUSE::Web::Util::RewriteXHTML->rewrite($html);
  } else {
    $html =~ s/^.*?<body[^>]*>//si;
    $html =~ s|</body>.*$||si;
    $html = $rewrite->($html) if $rewrite;
  }

  $html ||= "document '$name' not found on the server";

  $c->stash(".pause")->{doc} = $html;
  $c->render("pause_doc");
}

1;
