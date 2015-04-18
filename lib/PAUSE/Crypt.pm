use strict;
use warnings;
package PAUSE::Crypt;

use Crypt::Eksblowfish::Bcrypt qw( bcrypt en_base64 );

sub hash_password {
  my ($pw) = @_;

  $pw = substr $pw, 0, 72;
  my $hash = bcrypt($pw, '$2$12$' . en_base64( _randchar(16) ));
}

my(@saltset) = (qw(. /), 0..9, "A".."Z", "a".."z");

sub _randchar ($) {
  my($count) = @_;
  my $str = "";
  $str .= $saltset[int(rand(64))] while $count--;
  $str;
}

sub password_verify {
  my ($sent_pw, $crypt_pw) = @_;

  if (length $crypt_pw == 13) {
    my ($crypt_got) = crypt($sent_pw, $crypt_pw);
    return $crypt_got eq $crypt_pw;
  }

  my $pw = substr $sent_pw, 0, 72;
  my ($crypt_got) = bcrypt($sent_pw, $crypt_pw);
  return $crypt_got eq $crypt_pw;
}

sub maybe_upgrade_stored_hash {
  my ($arg) = @_;

  return if length $arg->{old_hash} > 13; # already bcrypt

  my $new_hash = hash_password($arg->{password});

  $arg->{dbh}->do(
    "UPDATE usertable SET password=? where user=?",
    +{},
    $new_hash,
    $arg->{username},
  );
}

1;
