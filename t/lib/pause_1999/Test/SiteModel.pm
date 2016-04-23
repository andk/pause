package pause_1999::Test::SiteModel;

use Moose;
extends 'WWW::Mechanize::Boilerplate';
with 'pause_1999::Test::SiteModel::Parser';

# Define a model that represents the web front-end so that we don't end up
# writing a lot of fragile tests just before the HTML and form parameters change
# underneath us.
#
# Allows us to do something like this:
#   $m->change_passwd->change_passwd__submit('foo', 'foo');
# Which goes to the change_passwd page and then changes the password, while
# doing all the boring boilerplate tasks like checking requests succeeded.

sub url { return '/pause/authenquery?ACTION=' . $_[0] }

sub set_user {
    my ( $self, $user ) = @_;
    $self->mech->{'basic_authentication'} = {};
    $self->mech->credentials( $user->username, $user->password );
    return $self;
}

__PACKAGE__->create_fetch_method(
    method_name      => 'homepage',
    page_description => 'homepage',
    page_url         => '/pause/authenquery',
);

# Create many simple fetch methods
my %fetch_pages = (
    change_passwd   => 'Change Password',
    delete_files    => 'Delete files',
    email_for_admin => 'Look up the forward email address',
    show_files      => 'Show my files',
);
while ( my ( $atom, $desc ) = each %fetch_pages ) {
    __PACKAGE__->create_fetch_method(
        method_name      => $atom,
        page_description => $desc,
        page_url         => url($atom),
    );
}

__PACKAGE__->create_form_method(
    method_name      => 'change_passwd__submit',
    form_number      => 1,
    form_description => 'change password form',
    assert_location  => url('change_passwd'),
    transform_fields => sub {
        my ( $self, $pw1, $pw2 ) = @_;
        return {
            pause99_change_passwd_pw1 => $pw1,
            pause99_change_passwd_pw2 => $pw2,
        };
    },
);

__PACKAGE__->create_link_method(
    method_name      => 'email_for_admin__yaml',
    link_description => 'YAML',
    find_link        => { text => 'YAML' },
    assert_location  => url('email_for_admin'),
 );

1;
