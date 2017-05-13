package Test::Pause99::Web::SimplePageTitle;

use strict;
use warnings;
use pause_1999::config;

use Storable qw/dclone/;
use Test::More;
use Test::Differences;
use base 'Test::Pause99::Web::Base';

my @groups = qw/mlrepr admin user public/;
my @groups_p = grep { $_ ne 'public' } @groups;

# Runs through the list of expected menu items, checks they appear
# for the three user types, and check they're only available for
# the relevant users
sub test_get_pages : Tests(248) {
    my $t = shift;

    my %user_actions = %{$pause_1999::config::DEFAULT_USER_ACTIONS};

    # Remove known 500s on the test box
    delete $user_actions{$_} for qw/check_xhtml index_users/;

    # What actions do we expect, based on the permissions
    my %expected;
    my %defaults = (
        map {
            $_ => { map { $_ => { status => 'no auth', auth_fail => 'soft' } }
                    qw/with_auth without_auth/ }
        } @groups
    );

    # You should be prompted to auth if you're not, and you need to be
    $defaults{'public'}{'with_auth'}
        = { status => 'no auth', auth_fail => 'hard' };

    for my $action ( sort keys %user_actions ) {
        my $page_data = { %{ $user_actions{$action} } };

        my $node = $expected{$action} = dclone \%defaults;

        # mlrepr is a fake group that admin is also part of
        if ( $page_data->{'priv'} eq 'admin' ) {
            $node->{'admin'}{'with_auth'}
                = { status => 'auth', header => $page_data->{'verb'} };
            $node->{'mlrepr'}{'with_auth'}
                = { status => 'auth', header => $page_data->{'verb'} };
        }

        elsif ( $page_data->{'priv'} eq 'mlrepr' ) {
            $node->{'mlrepr'}{'with_auth'}
                = { status => 'auth', header => $page_data->{'verb'} };
        }

        elsif ( $page_data->{'priv'} eq 'user' ) {
            $node->{$_}{'with_auth'}
                = { status => 'auth', header => $page_data->{'verb'} }
                for @groups_p;
        }

        elsif ( $page_data->{'priv'} eq 'public' ) {
            for my $permission (@groups) {
                for my $type (qw/with_auth without_auth/) {
                    $node->{$permission}->{$type}
                        = { status => 'auth', header => $page_data->{'verb'} }
                        unless ( $permission eq 'public'
                        && $type eq 'with_auth' );
                }
            }
        }
    }

    # Special case: mailpw is a noop if you hit it via authen_query
    $expected{'mailpw'}{$_}{'with_auth'}
        = { status => 'no auth', auth_fail => 'soft' }
        for @groups_p;

    # Special case: normal admin can show_ml_repr
    $expected{'show_ml_repr'}{'admin'} = $expected{'show_ml_repr'}{'mlrepr'};

    # Special case: admins can nuke the server(!!!)
    $expected{'coredump'}{'admin'}{'with_auth'} = $expected{'coredump'}{'mlrepr'}{'with_auth'}
        = { status => 500 };


    my %results;

    # Test for each user permission level
    for my $permission (@groups) {
        my ( $env, $author, $m ) = $t->new_environment(
            username  => 'ANDK',
            asciiname => 'blah',
            ugroup    => [ $permission eq 'mlrepr' ? 'admin' : $permission ],
        );

        if ( $permission ne 'public' ) {
            $m->set_user($author);
        }
        else {
            $m->clear_user;
        }

        # mlrepr is a lie -- it's an admin who's in list2user
        if ( $permission eq 'mlrepr' ) {
            $env->mod_dbh->do(
                "INSERT INTO list2user VALUES ('ANDK','ANDK');");
            $env->mod_dbh->do(
                "UPDATE users SET isa_list = 'y' WHERE userid = 'ANDK';");
        }

        for my $action ( sort keys %user_actions ) {
            my $data = $user_actions{$action};

            my $auth_url   = $m->url($action);
            my $unauth_url = $auth_url;
            $unauth_url =~ s/authen//;

            for (
                [ with_auth    => $auth_url ],
                [ without_auth => $unauth_url ]
                )
            {
                my ( $type, $url ) = @$_;

                note "[$permission] [$type] [$url]";
                if ( $action eq 'tail_logfile' ) {
                    local $PAUSE::Config->{PAUSE_LOG} = '/dev/null';
                    $m->mech->get($url);
                } else {
                    $m->mech->get($url);
                }

                my $result = $results{$action}->{$permission}->{$type} ||= {};

                if ( $m->mech->success() ) {
                    my $title = eval { $m->parse('title_only')->{'title'} }
                        || warn $@;
                    my $header = eval { $m->parse('title_only')->{'header'} }
                        || warn $@;

                    if ( $title eq 'PAUSE: ' . $action ) {
                        $result->{'status'} = 'auth';
                        $result->{'header'} = $header;

                    }
                    elsif ( $title =~ m/^PAUSE: menu/ ) {
                        $result->{'status'}    = 'no auth';
                        $result->{'auth_fail'} = 'soft';
                    }
                    else {
                        $result->{'status'} = 'unknown';
                    }
                }
                elsif ( $m->mech->status == 401 ) {
                    $result->{'status'}    = 'no auth';
                    $result->{'auth_fail'} = 'hard';
                }
                else {
                    $result->{'status'} = $m->mech->status;
                }

                eq_or_diff(
                    $result,
                    $expected{$action}->{$permission}->{$type},
                    "Action[$action] Permission[$permission] Type[$type] as expected"
                );

            }
        }
    }

}

1;
