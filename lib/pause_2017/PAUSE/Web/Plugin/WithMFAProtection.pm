package PAUSE::Web::Plugin::WithMFAProtection;

use Mojo::Base 'Mojolicious::Plugin';

our $VERSION = '1.00';

sub register {
    my ( $self, $app ) = @_;

    my $routes = $app->routes;

    $routes->add_condition(
        with_mfa_protection => sub {
            my ( $route, $c ) = @_;

            my $u = $c->active_user_record;

            # XXX: The active user record does not have mfa when an admin user is pretending someone else.
            return 1 unless $u->{mfa_secret32};

            my $otp = $c->req->body_params->param('otp');
            if (defined $otp and $otp ne '') {
                if ($otp =~ /\A[0-9]{6}\z/) {
                    return 1 if $c->app->pause->authenticator_for($u)->verify($otp);
                } elsif ($otp =~ /\A[a-z0-9]{5}\-[a-z0-9]{5}\z/) { # maybe one of the recovery codes?
                    require PAUSE::Crypt;
                    my $pause = $c->stash(".pause");
                    my @recovery_codes = split / /, $u->{mfa_recovery_codes} // '';
                    for my $code (@recovery_codes) {
                        if (PAUSE::Crypt::password_verify($otp, $code)) {
                            my $new_codes = join ' ', grep { $_ ne $code } @recovery_codes;
                            my $dbh = $c->app->pause->authen_connect;
                            my $tbl = $PAUSE::Config->{AUTHEN_USER_TABLE};
                            my $sql = "UPDATE $tbl SET mfa_recovery_codes = ?, changed = ?, changedby = ? WHERE user = ?";
                            $dbh->do($sql, undef, $new_codes, time, $pause->{User}{userid}, $u->{userid})
                              or push @{$pause->{ERROR}}, sprintf(qq{Could not enter the data into the database: <i>%s</i>.},$dbh->errstr);
                            return 1;
                        }
                    }
                }
            }
            # special case for upload
            if (my $upload = $c->req->upload("pause99_add_uri_httpupload")) {
                if ($upload->size) {
                    $PAUSE::Config->{INCOMING_TMP} =~ s|/$||;

                    my $filename = $upload->filename;
                    $filename =~ s(.*/)()gs;      # no slash
                    $filename =~ s(.*\\)()gs;     # no backslash
                    $filename =~ s(.*:)()gs;      # no colon
                    $filename =~ s/[^A-Za-z0-9_\-\.\@\+]//g; # only ASCII-\w and - . @ + allowed
                    my $to = "$PAUSE::Config->{INCOMING_TMP}/$filename";
                    # my $fhi = $upl->fh;
                    if (-f $to && -s _ == 0) { # zero sized files are a common problem
                        unlink $to;
                    }
                    if (eval { $upload->move_to($to) }){
                        warn "h1[File successfully copied to '$to']filename[$filename]";
                    } else {
                        die PAUSE::Web::Exception->new(ERROR => "Couldn't copy file '$filename' to '$to': $!");
                    }
                    unless ($upload->filename eq $filename) {
                        require Dumpvalue;
                        my $dv = Dumpvalue->new;
                        $c->req->param("pause99_add_uri_httpupload",$filename);
                        $c->req->param("pause99_add_uri_httpupload_renamed_from",$upload->filename);
                    }
                    $c->req->param("pause99_add_uri_httpupload_stashed", $filename);
                }
            }
            $c->render('mfa_check');
            return;
        }
    );

    $routes->add_shortcut(
        with_mfa_protection => sub {
            my ($route) = @_;
            return $route->requires( with_mfa_protection => 1 );
        }
    );

    $routes->add_shortcut(
        with_csrf_and_mfa_protection => sub {
            my ($route) = @_;
            return $route->requires( with_csrf_protection => 1, with_mfa_protection => 1 );
        }
    );

    return;
}

1;
