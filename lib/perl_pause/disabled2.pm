package perl_pause::disabled2;

use strict;

sub handler {
  my($r) = @_;
  $r->content_type("text/html");
  $r->send_http_header;
  print qq{
<HTML><HEAD><TITLE>Closed for Maintanance</TITLE></HEAD><BODY>
<H2>Dear visitor,</H2>

the PAUSE is closed for maintainance. I expect that service will be
up again at 1 p.m. GMT. On 2000-10-15 that is.<P>

Sorry for the inconvenience,<P>

andreas<BR>
Oct 15, 2000
</HTML>
};
  200;
}

1;
