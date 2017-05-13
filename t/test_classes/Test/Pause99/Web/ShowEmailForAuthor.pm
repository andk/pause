package Test::Pause99::Web::ShowEmailForAuthor;

use strict;
use warnings;

use Test::More;
use base 'Test::Pause99::Web::Base';

use pause_1999::Test::Environment;
use pause_1999::Test::Fixtures::Author;

sub test_basic : Tests(3) {
    my $t = shift;

    my $env = pause_1999::Test::Environment->new();

    # Need an admin user who can actually view this
    my $admin = pause_1999::Test::Fixtures::Author->new(
        environment => $env,
        username    => 'ADMIN',
        asciiname   => 'Admin user',
        ugroup      => [qw/admin/],
    );

    # Public email is in mod:users.email
    # If mod:users.cpan_mail_alias is publ, we always use that
    # If mod:users.cpan_mail_alias is secr, we use authen.secretemail
    # If there's nothing in either, we don't show an entry
    #
    # So the logic table looks something like

    my %expected = ( ADMIN => 'ADMIN@example.com', );

    for (
        #username public secretemail cpan_mail_alias shouldshow
        [ user1 => 'public@user1', 'secret@user1', 'publ', 'public@user1' ],
        [ user2 => 'public@user2', 'secret@user2', 'secr', 'secret@user2' ],
        [ user3 => 'public@user3', 'secret@user3', 'none', undef ],
        [ user4 => 'public@user4', undef, 'secr', [] ],
        )
    {
        my ($username,        $public_email, $secret_email,
            $cpan_mail_alias, $should_show
        ) = @$_;

        # Add to the database
        $env->authen_dbh->prepare( "
        INSERT INTO usertable ( user ) VALUES ( ? )
    " )->execute($username);
        $env->authen_dbh->prepare( "
        UPDATE usertable SET secretemail = ? WHERE user = ?
    " )->execute( $secret_email, $username ) if defined $secret_email;

        $env->mod_dbh->prepare( "
        INSERT INTO users ( userid, email, cpan_mail_alias ) VALUES ( ?, ?, ? )
    " )->execute( $username, $public_email, $cpan_mail_alias );

        if ( defined $should_show ) {
            if ( ref $should_show ) {
                $expected{$username} = undef;
            }
            else {
                $expected{$username} = $should_show;
            }
        }
    }

    my $m = $env->site_model($admin);

    my $received = $m->email_for_admin->parse()->{'email_for_admin'};

    my $yaml_received = $m->email_for_admin__yaml->parse()->{'yaml'};

    is_deeply( $received, \%expected, "Correct data in email_for_admin" );
    is_deeply( $yaml_received, \%expected,
        "Correct data in the YAML version" );

    # If we're a non-admin user, we should get nothing at all
    my $non_admin = pause_1999::Test::Fixtures::Author->new(
        environment => $env,
        username    => 'NONADMIN',
        asciiname   => 'Not an admin user',
    );

    $m->set_user($non_admin);
    $m->email_for_admin;
    $m->mech->title_is( 'PAUSE: menu',
        "No email_for_admin view for non-admins" );
}

1;
