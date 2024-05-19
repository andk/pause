use strict;
use warnings;

package PAUSE::MailAddress;
use Email::Address::XS;
use PAUSE ();

# use fields qw(address is_secret)

sub new {
  my($class,$hashref) = @_;
  bless $hashref, $class;
}

sub new_from_userid {
  my($class, $userid) = @_;

  my $authen_dbh = PAUSE::dbh('authen');
  my ($secretemail) = $authen_dbh->selectrow_array(
    "SELECT secretemail
    FROM $PAUSE::Config->{AUTHEN_USER_TABLE}
    WHERE $PAUSE::Config->{AUTHEN_USER_FLD}=?",
    undef,
    $userid,
  );

  my $me = {};

  if ($secretemail) {
    $me->{address} = $secretemail;
    $me->{is_secret} = 1;
  }

  my $mod_dbh = PAUSE::dbh('mod');
  my ($email, $fullname) = $mod_dbh->selectrow_array(
    "SELECT email, fullname FROM users WHERE userid=?",
    undef,
    $userid,
  );

  $fullname = Encode::decode('UTF-8', $fullname) if length $fullname;

  # The users.email column is NOT NULL, DEFAULT '', so we use || instead of //.
  #
  # Also, defaulting to USER@cpan.org is not going to age well, but for now,
  # I'm sticking to the existing behavior. -- rjbs, 2024-04-30
  $me->{address} ||= $email || "$userid\@cpan.org";

  $me->{email_object} = Email::Address::XS->new($fullname, $me->{address});

  bless $me, $class;
}

sub address { shift->{address} }
sub is_secret { shift->{is_secret} }

sub email_header_object {
  my ($self) = @_;
  PAUSE::Email->email_header_object_for_addresses($self->{email_object});
}

1;
