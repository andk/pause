package Test::Pause99::Web::Auth;

use strict;
use warnings;

use Time::Local qw/timelocal/;
use HTTP::Request::Common;
use pause_1999::Test::Environment;
use PAUSE::Crypt;

use Test::More;
use base 'Test::Pause99::Web::Base';

sub test_basic : Tests(12) {
    my $t = shift;
    my ( $env, $author, $m ) = $t->new_andreas();

    my $author_fullname = $author->fullname;

   # Before logging in we should have no last-seen, and the password should be
   # old-style crypted
    {
        my $user_data = $t->user_data( $env, $author->username );
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

        my $res = $m->mech->simple_request($req);
        is $res->code,              $code,    "$name: Code matches";
        like $res->decoded_content, $content, "$name: Content matches";
    }

    # Get the user's data from auth database

    {
        my $user_data = $t->user_data( $env, $author->username );
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

}

1;
