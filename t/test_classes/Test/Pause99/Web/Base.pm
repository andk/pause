package Test::Pause99::Web::Base;

use strict;
use warnings;

use base 'Test::Pause99::Base';
use Test::More;

sub new_environment {
    my ( $self, %options ) = @_;

    my ( $env, $author ) = $self->SUPER::new_environment( %options );
    my $site_model = $env->site_model($author);

    return ( $env, $author, $site_model );
}

sub new_andreas {
    my $self = shift;
    return $self->new_environment(
        username  => 'ANDK',
        asciiname => 'Andreas K',
    );
}

1;