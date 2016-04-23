#!perl

use strict;
use warnings;

use Test::More;
use pause_1999::Test::Environment;

my ( $env, $author ) = pause_1999::Test::Environment->new_with_author(
    username  => 'ANDK',
    asciiname => 'Andreas K',
);

my $m = $env->site_model($author);

# Try some invalid form submissions
for (
    [ '',    '',    "Empty",        qr/Please fill in the form/ ],
    [ 'foo', 'moo', "Non-matching", qr/passwords didn't match/ ],
    )
{
    my ( $pw1, $pw2, $name, $match ) = @$_;
    $m->change_passwd->change_passwd__submit( $pw1, $pw2 );
    $m->mech->content_like( $match, "$name passwords caught" );
}

# Now try a matching password
$m->change_passwd->change_passwd__submit( 'moo', 'moo' );
$m->mech->content_like( qr/New password stored and enabled/,
    "New password message shown" );

# 401 if we re-use old credentials
$m->homepage;
is( $m->mech->status, 401, "Old auth fails now we have a new password" );

# New credentials work
$m->mech->credentials( $author->username, 'moo' );
$m->homepage;
is( $m->mech->status, 200, "New password authenticates successfully" );

done_testing();
