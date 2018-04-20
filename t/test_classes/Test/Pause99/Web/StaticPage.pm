package Test::Pause99::Web::StaticPage;

use strict;
use warnings;

use Time::Local qw/timelocal/;
use HTTP::Request::Common;
use pause_1999::Test::Environment;
use PAUSE::Crypt;

use Test::More;
use base 'Test::Pause99::Web::Base';

sub test_static : Tests(5) {
    my $t = shift;
    my ( $env, $author, $m ) = $t->new_andreas();

    $m->pausecss;
    is $m->mech->status, 200, "Code matches";
    $m->mech->content_like( qr/actionresponse/,
        "Content matches" );

    $m->unknownpath;
    is $m->mech->status, 404, "Code matches";

    $m->challengereadme;
    is $m->mech->status, 200, "Code matches";
    $m->mech->content_like( qr/Letsencrypt/,
        "Content matches" );

}

1;
