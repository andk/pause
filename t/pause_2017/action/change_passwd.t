use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_change_passwd_pw1 => "new_pass",
    pause99_change_passwd_pw2 => "new_pass",
    pause99_change_passwd_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for_get('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        $t->$method("$path?ACTION=change_passwd")
          ->text_is("h2.firstheader", "Change Password");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    plan skip_all => 'SKIP for now';
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for_post('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my %form = %$default;
        my $t = Test::PAUSE::Web->new;
        $t->$method("$path?ACTION=change_passwd", \%form);
        # note $t->content;
    }
};

subtest 'safe_post: basic' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for_safe_post('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my %form = %$default;
        my $t = Test::PAUSE::Web->new;
        $t->$method("$path?ACTION=change_passwd", \%form)
          ->text_is("h2.firstheader", "Change Password")
          ->text_like("p.password_stored", qr/New password stored/);
        is $t->deliveries => 1, "one delivery for admin";
        # note $t->content;
    }
};

subtest 'safe_post: passwords mismatch' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for_safe_post('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_change_passwd_pw2 => "wrong_pass",
        );
        $t->$method("$path?ACTION=change_passwd", \%form)
          ->text_is("h2", "Error")
          ->text_like("p.error_message", qr/The two passwords didn't match./);
        ok !$t->deliveries, "no delivery for admin";
        # note $t->content;
    }
};

subtest 'safe_post: only one password' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for_safe_post('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_change_passwd_pw2 => undef,
        );
        $t->$method("$path?ACTION=change_passwd", \%form)
          ->text_is("h2", "Error")
          ->text_like("p.error_message", qr/You need to fill in the same password in both fields./);
        ok !$t->deliveries, "no delivery for admin";
        # note $t->content;
    }
};

subtest 'safe_post: no password' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for_safe_post('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_change_passwd_pw1 => undef,
            pause99_change_passwd_pw2 => undef,
        );
        $t->$method("$path?ACTION=change_passwd", \%form)
          ->text_is("h2", "Error")
          ->text_like("p.error_message", qr/Please fill in the form with passwords./);
        ok !$t->deliveries, "no delivery for admin";
        # note $t->content;
    }
};

done_testing;
