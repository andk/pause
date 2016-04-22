package perl_pause::disabled2;


=pod

I never intended to have a super-quick solution.

This here is one that is only enabled at startup-time so we need to
create an /etc/PAUSE.CLOSED file with a meaningful sentence and
restart the server. Later we need to remove the /etc/PAUSE.CLOSED file
and again restart the server. Between the two restarts all users see
the message.

=cut

use strict;

sub handler {
  my($req) = @_;
  my $res = $req->new_response(200);
  $res->content_type("text/html");
  open my $fh, "/etc/PAUSE.CLOSED";
  local $/;
  my $mess = <$fh>;
  $mess ||= qq{please retry in a few seconds};
  $res->body([qq{<html><head><title>Closed for Maintanance</title></head><body>
<h2>Dear visitor,</h2>},
    $mess,
        qq{</html>}]);
  $res->finalize;
}

1;
