package pause_1999::Test::Config;

use strict;
use warnings;
use Test::More;

BEGIN { $INC{'PrivatePAUSE.pm'} = 1; }

use PAUSE;

sub set_mail_mailer {
    my ( $class, $args ) = @_;
    $PAUSE::Config->{MAIL_MAILER} = $args;
    return $PAUSE::Config;
}

sub set_authen_db {
    my ( $class, $mysql ) = @_;
    return $class->_set_db( $mysql, 'AUTHEN' );
}

sub set_mod_db {
    my ( $class, $mysql ) = @_;
    return $class->_set_db( $mysql, 'MOD' );
}

sub _set_db {
    my ( $class, $mysql, $name ) = @_;

    $PAUSE::Config->{$name . '_DATA_SOURCE_NAME'} = $mysql->dsn;
    $PAUSE::Config->{$name . '_DATA_SOURCE_USER'} = undef;
    $PAUSE::Config->{$name . '_DATA_SOURCE_PW'} = undef;

    return $PAUSE::Config;
}

1;
