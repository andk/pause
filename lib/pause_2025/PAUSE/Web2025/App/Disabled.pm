package PAUSE::Web2025::App::Disabled;

use Mojo::Base -base;
use Plack::Request;
use Plack::Response;

sub to_app {
  my $self = shift;

  return sub {
    my $req = Plack::Request->new(shift);
    my $res = $req->new_response(200);
    $res->content_type("text/html");
    open my $fh, "/etc/PAUSE.CLOSED";
    local $/;
    my $mess = <$fh>;
    $mess ||= qq{please retry in a few seconds};
    $res->body([<<"HTML"]);
<!doctype html>
<html>
<head><title>Closed for Maintanance</title></head>
<body>
<h2>Dear visitor,</h2>},
$mess,
</html>
HTML
    $res->finalize;
  };
}

1;
