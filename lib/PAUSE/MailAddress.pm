package PAUSE::MailAddress;
use PAUSE ();
use strict;

# use fields ADDRESS, IS_SECRET

sub new {
  my($class,$hashref) = @_;
  bless $hashref, $class;
}

sub new_from_userid {
  my($class,$userid) = @_;
  my $dbh = DBI->connect(
                         $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
                         $PAUSE::Config->{MOD_DATA_SOURCE_USER},
                         $PAUSE::Config->{MOD_DATA_SOURCE_PW},
                         { RaiseError => 1 }
                        )
      or Carp::croak(qq{Can't DBI->connect(): $DBI::errstr});
  my $dsn = $PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME};
  my(undef,undef,$dbname) = split /:/, $dsn;
  my $sth = $dbh->prepare("SELECT secretemail
                             FROM $dbname.$PAUSE::Config->{AUTHEN_USER_TABLE}
                             WHERE $PAUSE::Config->{AUTHEN_USER_FLD}=?");
  $sth->execute($userid);
  my $me = {};
  if ($sth->rows > 0) {
    ($me->{address}) = $sth->fetchrow_array;
    $me->{is_secret} = 1;
  } else {
    $sth = $dbh->prepare("SELECT email FROM users WHERE userid=?");
    $sth->execute($userid);
    return if $sth->rows == 0;
    ($me->{address}) = $sth->fetchrow_array;
  }
  bless $me, $class;
}

sub address { shift->{ADDRESS} }
sub is_secret { shift->{IS_SECRET} }

1;
