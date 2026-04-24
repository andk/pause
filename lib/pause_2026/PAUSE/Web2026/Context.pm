package PAUSE::Web2026::Context;

use Mojo::Base "PAUSE::Web::Context";

has config => sub { require PAUSE::Web2026::Config; PAUSE::Web2026::Config->new };
has template_paths => sub { [ "lib/pause_2017/templates", "lib/pause_2026/templates" ] };
has controller_namespaces => sub { [ "PAUSE::Web::Controller", "PAUSE::Web2026::Controller" ] };

1;

