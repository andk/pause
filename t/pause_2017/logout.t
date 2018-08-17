use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::PAUSE::Web;
use utf8;
use HTTP::Status qw/:constants/;

Test::PAUSE::Web->setup;

subtest 'logout 1: redirect with Cookie' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $rand = rand 1;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path");
        my $res = $t->get("$path?logout=1$rand");
    SKIP: {
        skip "FIXME: Not found?", 1;
        is $res->code => HTTP_UNAUTHORIZED;
        }
    }
};

subtest 'logout 2: redirect to Badname:Badpass@Server URL' => sub {
    plan skip_all => "WWW::Mechanize/LWP::UserAgent currently ignores userinfo";
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $rand = rand 1;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path");
        my $res = $t->get("$path?logout=2$rand");
        is $res->code => HTTP_UNAUTHORIZED;
    }
};

subtest 'logout 3: Quick direct 401' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $rand = rand 1;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path");
        my $res = $t->get("$path?logout=3$rand");
        is $res->code => HTTP_UNAUTHORIZED;
    }
};

done_testing;
