use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::PAUSE::Web;
use HTTP::Status qw/:constants/;
use utf8;

Test::PAUSE::Web->setup;

subtest 'basic' => sub {
    my $test = Test::PAUSE::Web->tests_for('user');
    my ($path, $user) = @$test;
    my $t = Test::PAUSE::Web->new(user => $user);
    my $res = $t->get("$path");;
    ok $res->is_success;
};

subtest 'lower case' => sub {
    my $test = Test::PAUSE::Web->tests_for('user');
    my ($path, $user) = @$test;
    my $t = Test::PAUSE::Web->new(user => lc $user);
    my $res = $t->get("$path");;
    ok $res->is_success;
};

subtest 'wrong password' => sub {
    my $test = Test::PAUSE::Web->tests_for('user');
    my ($path, $user) = @$test;
    my $t = Test::PAUSE::Web->new(user => $user, pass => "WRONG PASS");
    my $res = $t->get("$path");;
    ok !$res->is_success;
    is $res->code => HTTP_UNAUTHORIZED;
};

subtest 'unknown user' => sub {
    my $test = Test::PAUSE::Web->tests_for('user');
    my ($path, $user) = @$test;
    my $t = Test::PAUSE::Web->new(user => "UNKNOWN");
    my $res = $t->get("$path");;
    ok !$res->is_success;
    is $res->code => HTTP_UNAUTHORIZED;
};

done_testing;
