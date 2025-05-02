use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::PAUSE::Web;
use HTTP::Status qw/:constants/;
use utf8;

Test::PAUSE::Web->setup;

subtest 'for 2017 app' => sub {
    subtest 'basic' => sub {
        my $test = Test::PAUSE::Web->tests_for('user');
        my ($path, $user) = @$test;
        my $t   = Test::PAUSE::Web->new(user => $user);
        my $res = $t->get("$path");
        ok $res->is_success;
    };

    subtest 'lower case' => sub {
        my $test = Test::PAUSE::Web->tests_for('user');
        my ($path, $user) = @$test;
        my $t   = Test::PAUSE::Web->new(user => lc $user);
        my $res = $t->get("$path");
        ok $res->is_success;
    };

    subtest 'wrong password' => sub {
        my $test = Test::PAUSE::Web->tests_for('user');
        my ($path, $user) = @$test;
        my $t   = Test::PAUSE::Web->new(user => $user, pass => "WRONG PASS");
        my $res = $t->get("$path");
        ok !$res->is_success;
        is $res->code => HTTP_UNAUTHORIZED;
    };

    subtest 'unknown user' => sub {
        my $test = Test::PAUSE::Web->tests_for('user');
        my ($path, $user) = @$test;
        my $t   = Test::PAUSE::Web->new(user => "UNKNOWN");
        my $res = $t->get("$path");
        ok !$res->is_success;
        is $res->code => HTTP_UNAUTHORIZED;
    };

    subtest 'disallowed action for an anonymous user' => sub {
        my $test = Test::PAUSE::Web->tests_for('user');
        my ($path, $user) = @$test;
        my $t   = Test::PAUSE::Web->new;
        my $res = $t->get("/pause/authenquery/?ACTION=add_user");
        ok !$res->is_success;
        is $res->code => HTTP_UNAUTHORIZED;
    };

    subtest 'disallowed action for a user' => sub {
        my $test = Test::PAUSE::Web->tests_for('user');
        my ($path, $user) = @$test;
        my $t   = Test::PAUSE::Web->new(user => $user);
        my $res = $t->get("/pause/authenquery/?ACTION=add_user");
        ok !$res->is_success;
        is $res->code => HTTP_FORBIDDEN;
    };
};

subtest 'for 2025 app' => sub {
    subtest 'basic' => sub {
        my $test = Test::PAUSE::Web->tests_for('user');
        my ($path, $user) = @$test;
        my $t   = Test::PAUSE::Web->new;
        my $res = $t->login(user => $user);
        ok $res->is_success;
        ok my @redirects = $res->redirects, "login succeeded and redirected";
        is $redirects[0]->header('Location')->path => '/';
    };

    subtest 'lower case' => sub {
        my $test = Test::PAUSE::Web->tests_for('user');
        my ($path, $user) = @$test;
        my $t   = Test::PAUSE::Web->new(user => lc $user);
        my $res = $t->login(user => lc $user);
        ok $res->is_success;
        ok my @redirects = $res->redirects, "login succeeded and redirected";
        is $redirects[0]->header('Location')->path => '/';
    };

    subtest 'wrong password' => sub {
        my $test = Test::PAUSE::Web->tests_for('user');
        my ($path, $user) = @$test;
        my $t   = Test::PAUSE::Web->new;
        my $res = $t->login(user => $user, pass => "WRONG PASS");
        ok !(my @redirects = $res->redirects), "login failed and not redirected";
    };

    subtest 'unknown user' => sub {
        my $test = Test::PAUSE::Web->tests_for('user');
        my ($path, $user) = @$test;
        my $t   = Test::PAUSE::Web->new;
        my $res = $t->login(user => "UNKNOWN");
        ok !(my @redirects = $res->redirects), "login failed and not redirected";
    };

    subtest 'disallowed action for an anonymous user' => sub {
        my $test = Test::PAUSE::Web->tests_for('user');
        my ($path, $user) = @$test;
        my $t   = Test::PAUSE::Web->new;
        my $res = $t->get("/admin/add_user");
        ok !$res->is_success;
        is $res->code => HTTP_FORBIDDEN;
    };

    subtest 'disallowed action for a user' => sub {
        my $test = Test::PAUSE::Web->tests_for('user');
        my ($path, $user) = @$test;
        my $t   = Test::PAUSE::Web->new;
        $t->login(user => $user);
        my $res = $t->get("/admin/add_user");
        ok !$res->is_success;
        is $res->code => HTTP_FORBIDDEN;
    };
};

done_testing;
