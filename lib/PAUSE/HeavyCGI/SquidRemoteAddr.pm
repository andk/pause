package Apache::HeavyCGI::SquidRemoteAddr;
use Apache::Constants qw(:common);
use constant SRA_DEBUG => 0;
use strict;
use vars qw($VERSION $NoHeader_warned);
$VERSION = sprintf "%d.%03d", q$Revision: 1.5 $ =~ /(\d+)\.(\d+)/;


sub handler {
  my $r = shift;

  my $xff = $r->header_in('X-Forwarded-For')||"";
  if (my($ip) = $xff =~ /([^,\s]+)$/) {
    $r->connection->remote_ip($ip);
  } else {
    warn sprintf "No IP in X-Forwarded-For[%s]", $xff
	unless $NoHeader_warned++;
  }
  warn sprintf "HERE Headers[%s]", join " ", $r->headers_in if SRA_DEBUG;

  DECLINED;
}

1;

__END__

=head1 NAME

Apache::HeavyCGI::SquidRemoteAddr - Pass X-Forwarded-For Header through as remote_ip

=head1 SYNOPSIS

 PerlPostReadRequestHandler  Apache::HeavyCGI::SquidRemoteAddr

=head1 DESCRIPTION

Author Vivek Khera, taken from his mod_perl_tuning document.

=cut

