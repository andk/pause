package perl_pause::disabled;

use strict;

sub handler {
  my($req) = @_;
  my $res = $req->new_response(200);
  $res->content_type("text/html");
  $res->body([qq{
<HTML><HEAD><TITLE>disabled</TITLE></HEAD><BODY>
<H2>Moved...</H2>

the PAUSE has moved again to a new machine. You are not simply
redirected to the new server, because this has caused confusion for
other users. So please connect to

<H2>
<A HREF="http://p11.speed-link.de">p11.speed-link.de (non-SSL PAUSE)</A>
</H2>

The nameserver will be taught about the new address of the server
tomorrow, so then you can connect to "pause.kbx.de" again. At the time
of this writing I am not able to set up SSL on the new host. Sorry for
the inconvenience, I hope, you at least enjoy the 2 MBit line.<P>

andreas<BR>
Dec 20, 1998
</HTML>
}]);
  $res->finalize;
}

1;
