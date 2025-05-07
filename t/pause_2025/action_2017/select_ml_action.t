use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $mailing_list = {
    SUBMIT_pause99_add_user_Definitely => 1,
    pause99_add_user_userid => "MAILLIST",
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
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=select_ml_action");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        $t->post_ok("$path?ACTION=add_user", $mailing_list);

        $t->mod_db->insert("list2user", {
            maillistid => "MAILLIST",
            userid => "TESTUSER",
        }, {ignore => 1});

        my %form = %$default;
        $t->post_ok("$path?ACTION=select_ml_action", \%form);
        # note $t->content;
    }
};

done_testing;
