use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;

my $default = {
    pause99_change_user_status_user => "TESTUSER",
    pause99_change_user_status_new_ustatus => "nologin",
    pause99_change_user_status_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        $t->get_ok("/admin/change_user_status");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my %form = %$default;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        my $res = $t->post("/admin/change_user_status", \%form);
        ok !$res->is_success && $res->code == 403, "Forbidden";
        like $res->content => qr/Failed CSRF check/;
        # note $t->content;
    }
};

subtest 'post_with_token: basic' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my %form = %$default;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        $t->post_with_token_ok("/admin/change_user_status", \%form)
          ->text_like("div.messagebox p", qr/status has changed from \w+ to nologin/);
        is $t->deliveries => 2, "two deliveries for admin";
        # note $t->content;
    }
};

subtest 'post_with_token: user not found' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my %form = (
            %$default,
            pause99_change_user_status_user => 'UNKNOWN',
        );
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        $t->post_with_token_ok("/admin/change_user_status", \%form)
          ->text_like("div.messagebox p", qr/User UNKNOWN is not found/);
        is $t->deliveries => 0, "no deliveries for admin";
        # note $t->content;
    }
};

subtest 'post_with_token: ustatus not changed' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my %form = %$default;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        $t->post_with_token_ok("/admin/change_user_status", \%form)
          ->text_like("div.messagebox p", qr/status has changed from \w+ to nologin/);
        is $t->deliveries => 2, "two deliveries for admin";
        # note $t->content;

        # nologin to nologin
        $t->post_with_token_ok("/admin/change_user_status", \%form)
          ->dom_not_found("div.messagebox p");
        is $t->deliveries => 0, "no deliveries for admin";
    }
};

subtest 'post_with_token: unknown ustatus' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my %form = (
            %$default,
            pause99_change_user_status_new_ustatus => 'unknown',
        );
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        $t->post_with_token_ok("/admin/change_user_status", \%form)
          ->dom_not_found("div.messagebox p");
        is $t->deliveries => 0, "no deliveries for admin";
    }
};

done_testing;
