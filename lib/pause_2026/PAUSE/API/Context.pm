package PAUSE::API::Context;

use Mojo::Base "PAUSE::Web::Context";

has config => sub {};
has template_paths => sub { [] };
has controller_namespaces => sub { ["PAUSE::API::Controller"] };

1;


