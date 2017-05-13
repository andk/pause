package Test::Pause99::Base;

use strict;
use warnings;

use base 'Test::Class';
use Test::More;
use pause_1999::Test::Environment;

sub warble : Test(startup) {
    note ref shift();
}

sub new_environment {
    my ( $self, %options ) = @_;
    # ($env, $author)
    return pause_1999::Test::Environment->new_with_author(
        %options
    );
}

sub user_data {
    my ( $self, $env, $user ) = @_;
    my $user_data_st
        = $env->authen_dbh->prepare("SELECT * FROM usertable WHERE user = ?");
    $user_data_st->execute($user);
    return $user_data_st->fetchrow_hashref;
}

1;