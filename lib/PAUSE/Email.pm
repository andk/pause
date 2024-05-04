use v5.36.0;
package PAUSE::Email;

use Email::Address::XS ();
use Email::MIME::Header::AddressList ();

sub email_header_object_for_addresses ($class, @addresses) {
  return Email::MIME::Header::AddressList->new(@addresses);
}

sub report_email_header_object ($class) {
  require PAUSE;

  my @addrs = split /\s*,\s*/, $PAUSE::Config->{ADMIN};

  die "No PAUSE config entry for ADMIN!?" unless @addrs;

  my @objects = map {; Email::Address::XS->new(undef, $_) } @addrs;

  return $class->email_header_object_for_addresses(@objects);
}

sub contact_email_header_object ($class) {
  require PAUSE;

  return $class->email_header_object_for_addresses(
    Email::Address::XS->new("PAUSE Admins", $PAUSE::Config->{CONTACT_ADDRESS})
  );
}

sub noreply_email_header_object ($class) {
  require PAUSE;

  return $class->email_header_object_for_addresses(
    Email::Address::XS->new("Perl Authors Upload Server", $PAUSE::Config->{UPLOAD})
  );
}

sub is_valid_email ($class, $string) {
  my $parse = Email::Address::XS->parse_bare_address($string);

  # None at all!  That's not a valid email.
  return unless $parse;

  # This could mean >1 address in $string, or various forms of "not a useful
  # email" like "no domain".
  return unless $parse->is_valid;

  return 1;
}

1;
