use strict;
use warnings;

use PAUSE::Crypt;
use Test::More;

my $password = "Scrapple?  Yum!!";
my $salt     = "We luv scrapple.";

my $crypt    = 'We.cEH7/uontQ';
my $bcrypt   = '$2$10$T0SeZFT0GFLhakDuaEvjJebxqvqD2ndcK00JVvsAK0IvYPsMqMO1y';

ok(
  PAUSE::Crypt::password_verify($password, $crypt),
  "we can verify DES password",
);

ok(
  PAUSE::Crypt::password_verify($password, $bcrypt),
  "we can verify bcrypt password",
);

my $new_hash = PAUSE::Crypt::hash_password($password);
ok(
  PAUSE::Crypt::password_verify($password, $new_hash),
  "we can verify newly-generated bcrypt password",
);

ok(
  ! PAUSE::Crypt::password_verify('bogus', $crypt),
  "we reject bad pw against crypt hash",
);

ok(
  ! PAUSE::Crypt::password_verify('bogus', $bcrypt),
  "we reject bad pw against bcrypt hash",
);

ok(
  ! PAUSE::Crypt::password_verify('bogus', $new_hash),
  "we reject bad pw against new hash",
);

done_testing;
