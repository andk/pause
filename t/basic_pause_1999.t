#!perl

use strict;
use warnings;

use Test::More;

use Time::Local qw/timelocal/;
use HTTP::Request::Common;
use pause_1999::Test::Environment;
use PAUSE::Crypt;

my ( $env, $author ) = pause_1999::Test::Environment->new_with_author(
    username  => 'ANDK',
    asciiname => 'Andreas K',
);

my $test = $env->plack_test();

my $author_fullname = $author->fullname;

# Before logging in we should have no last-seen, and the password should be
# old-style crypted
{
    my $user_data = user_data( $author->username );
    is( $user_data->{'lastvisit'}, undef, "User has never been seen" );
    is( $user_data->{'password'},
        $author->password_crypted, "Oldstyle crypt() password" );
}

# Test basic authentication
my @no_auth = ( 401 => qr/Authorization required/ );
for (
    [ undef, @no_auth, 'No username or password' ],
    [ [ foo  => 'foo' ], @no_auth, 'Unknown user' ],
    [ [ andk => 'foo' ], @no_auth, 'Wrong password' ],
    [   [ $author->username, $author->password ],
        200 => qr($author_fullname),
        'Correct credentials'
    ],
    )
{
    my ( $credentials, $code, $content, $name ) = @$_;
    my $req = GET "/pause/authenquery";
    if ($credentials) {
        $req->headers->authorization_basic(@$credentials);
    }

    my $res = $test->request($req);
    is $res->code,              $code,    "$name: Code matches";
    like $res->decoded_content, $content, "$name: Content matches";
}

# Get the user's data from auth database

{
    my $user_data = user_data( $author->username );
    my @time_pieces = reverse split( /\D/, $user_data->{'lastvisit'} );
    $time_pieces[4] -= 1;
    my $last_seen_epoch = timelocal(@time_pieces);
    my $ago             = time - $last_seen_epoch;
    ok( $ago < 120, "User has now been seen today ($ago seconds ago)" );
    ok( PAUSE::Crypt::password_verify(
            $author->password, $user_data->{'password'}
        ),
        "Password updated to bcrypt"
    );
}

# Should have update last_seen

sub user_data {
    my $user = shift;
    my $user_data_st
        = $env->authen_dbh->prepare("SELECT * FROM usertable WHERE user = ?");
    $user_data_st->execute($user);
    return $user_data_st->fetchrow_hashref;
}

done_testing();
