use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $new_user = {
    SUBMIT_pause99_add_user_Definitely => 1,
    pause99_add_user_userid => "NEWUSER",
    pause99_add_user_fullname => "new user",
    pause99_add_user_email => "new_user\@localhost.localdomain",
    pause99_add_user_homepage => "http://home.page",
};

my $new_mailing_list = {
    SUBMIT_pause99_add_user_Definitely => 1,
    pause99_add_user_userid => "MAILLIST",
    pause99_add_user_fullname => "Mailing List",
    pause99_add_user_email => "ml\@localhost.localdomain",
    pause99_add_user_subscribe => "how to subscribe",
};

my $default = {
    HIDDENNAME => "TESTUSER",
    ACTIONREQ => "edit_ml",
    pause99_select_ml_action_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        $t->get_ok("/admin/add_user");
        # note $t->content;
    }
};

subtest 'post: ordinary user' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        $t->reset_fixture;
        $t->post_ok("/admin/add_user", $new_user);
        # note $t->content;

        # new user exists
        my $rows = $t->mod_db->select('users', ['*'], {
            userid => $new_user->{pause99_add_user_userid},
        });
        is @$rows => 1;
        for my $key (qw/userid homepage fullname/) {
            is $rows->[0]{$key} => $new_user->{"pause99_add_user_$key"}, "$key is stored correctly";
        }
        is $rows->[0]{email} => 'CENSORED'; # email in the user table is always CENSORED

        # email tests; censored email shouldn't be disclosed to admins
        my @deliveries = $t->deliveries;
        my @welcome_emails = grep { $_->header('Subject') =~ /Welcome/ } @deliveries;
        is @welcome_emails => 2;
        my ($welcome_for_user) = grep { $_->header('To') =~ /new_user/ } @welcome_emails;
        like $welcome_for_user->body => qr/email:\s+new_user\@localhost/;

        my ($welcome_for_admins) = grep { $_->header('To') =~ /admin/ } @welcome_emails;
        unlike $welcome_for_admins->body => qr/email:\s+new_user\@localhost/;
        like $welcome_for_admins->body => qr/email:\s+CENSORED/;
    }
};

subtest 'post: user with an accent in their name' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        $t->reset_fixture;
        $t->post_ok("/admin/add_user", {
            %$new_user,
            pause99_add_user_fullname => "T\xc3\xa9st Name",
        });
        # note $t->content;

        # new user exists
        my $rows = $t->mod_db->select('users', ['*'], {
            userid => $new_user->{pause99_add_user_userid},
        });
        is @$rows => 1;
    SKIP: {
        skip "FIXME: seems not so stable; probably needs more explicit configuration", 1;
        is $rows->[0]{fullname} => "T\xc3\xa9st Name";
        }
    }
};

subtest 'post: soundex' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        my %copied_user = %$new_user;
        $copied_user{pause99_add_user_fullname} = 'new user';
        $copied_user{SUBMIT_pause99_add_user_Soundex} = 1;
        delete $copied_user{SUBMIT_pause99_add_user_Definitely};

        $t->reset_fixture;
        $t->post_ok("/admin/add_user", {
            %copied_user,
        });
        # note $t->content;

        # new user exists
        my $rows = $t->mod_db->select('users', ['*'], {
            userid => $new_user->{pause99_add_user_userid},
        });
        is @$rows => 1;
    }
};

subtest 'post: soundex error: similar name' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        my %copied_user = %$new_user;
        $copied_user{pause99_add_user_fullname} = 'new nome';
        $copied_user{SUBMIT_pause99_add_user_Soundex} = 1;
        delete $copied_user{SUBMIT_pause99_add_user_Definitely};

        $t->reset_fixture;
        $t->post_ok("/admin/add_user", {
            %copied_user,
        });
        $t->text_like('h3', qr/Not submitting NEWUSER, maybe we have a duplicate/);
        # note $t->content;

        # new user does not exist
        my $rows = $t->mod_db->select('users', ['*'], {
            userid => $new_user->{pause99_add_user_userid},
        });
        is @$rows => 0;
    }
};

subtest 'post: metaphone' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        my %copied_user = %$new_user;
        $copied_user{pause99_add_user_fullname} = 'new user';
        $copied_user{SUBMIT_pause99_add_user_Metaphone} = 1;
        delete $copied_user{SUBMIT_pause99_add_user_Definitely};

        $t->reset_fixture;
        $t->post_ok("/admin/add_user", {
            %copied_user,
        });
        # note $t->content;

        # new user exists
        my $rows = $t->mod_db->select('users', ['*'], {
            userid => $new_user->{pause99_add_user_userid},
        });
        is @$rows => 1;
    }
};

subtest 'post: metaphone error: similar name' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        my %copied_user = %$new_user;
        $copied_user{pause99_add_user_fullname} = 'new nome';
        $copied_user{SUBMIT_pause99_add_user_Metaphone} = 1;
        delete $copied_user{SUBMIT_pause99_add_user_Definitely};

        $t->reset_fixture;
        $t->post_ok("/admin/add_user", {
            %copied_user,
        });
        $t->text_like('h3', qr/Not submitting NEWUSER, maybe we have a duplicate/);
        # note $t->content;

        # new user does not exist
        my $rows = $t->mod_db->select('users', ['*'], {
            userid => $new_user->{pause99_add_user_userid},
        });
        is @$rows => 0;
    }
};

subtest 'post: metaphone error: completely duplicated' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        my %copied_user = %$new_user;
        $copied_user{SUBMIT_pause99_add_user_Metaphone} = 1;
        delete $copied_user{SUBMIT_pause99_add_user_Definitely};

        $t->reset_fixture;
        $t->post_ok("/admin/add_user", {
            %copied_user,
        });

        # new user exists
        my $rows = $t->mod_db->select('users', ['*'], {
            userid => $new_user->{pause99_add_user_userid},
        });
        is @$rows => 1;

        $t->post_ok("/admin/add_user", {
            %copied_user,
        });
        $t->text_like('h3', qr/Not submitting NEWUSER, maybe we have a duplicate/);
        # note $t->content;
    }
};

subtest 'post: mailing list' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        $t->reset_fixture;
        $t->post_ok("/admin/add_user", $new_mailing_list);
        # note $t->content;

        # new mailing list exists
        my $rows = $t->mod_db->select('maillists', ['*'], {
            maillistid => $new_mailing_list->{pause99_add_user_userid},
        });
        is @$rows => 1;

        # new user also exists
        $rows = $t->mod_db->select('users', ['*'], {
            userid => $new_mailing_list->{pause99_add_user_userid},
        });
        is @$rows => 1;
    }
};

subtest 'get: retrieve a stored session' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        my %requested_user;
        for my $key (keys %$new_user) {
            next if $key =~ /SUBMIT/;
            my $new_key = $key =~ s/add_user/request_id/r;
            $requested_user{$new_key} = $new_user->{$key};
        }
        $requested_user{pause99_request_id_rationale} = 'Rational to request PAUSE ID';
        $requested_user{SUBMIT_pause99_request_id_sub} = 1;

        $t->reset_fixture;
        $t->post_ok("/public/request_id", \%requested_user);
        my ($email) = map {$_->body} $t->deliveries;
        my ($userid) = $email =~ m!https://.+?/admin/add_user\?USERID=([^&\s]+)!;
        like $userid => qr/\A\d+_\w+\z/;
        $t->clear_deliveries;

        $t->get_ok("/admin/add_user?USERID=$userid");
        # note $t->content;

        for my $key (keys %$new_user) {
            next if $key =~ /SUBMIT/;
            is $t->dom->at("input[name=$key]")->attr('value') => $new_user->{$key}, "$key is set correctly";
        }
    }
};

done_testing;
