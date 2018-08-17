use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $new_user = {
    SUBMIT_pause99_add_user_Definitely => 1,
    pause99_add_user_userid => "NEWUSER",
    pause99_add_user_fullname => "full name",
    pause99_add_user_email => "new_user\@localhost.localdomain",
    pause99_add_user_homepage => "http://home.page",
};

my $new_mailing_list = {
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
        $t->get_ok("$path?ACTION=add_user");
        # note $t->content;
    }
};

subtest 'post: ordinary user' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->post_ok("$path?ACTION=add_user", $new_user);
        # note $t->content;
    }
};

subtest 'post: mailing list' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->post_ok("$path?ACTION=add_user", $new_mailing_list);
        # note $t->content;
    }
};

done_testing;
