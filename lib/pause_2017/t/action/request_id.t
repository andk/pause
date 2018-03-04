use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_request_id_fullname => 'full name',
    pause99_request_id_email => 'test@localhost.localdomain',
    pause99_request_id_homepage => 'none',
    pause99_request_id_userid => 'NEWUSER',
    pause99_request_id_rationale => 'Hello, my ratoinale is to test PAUSE',
    SUBMIT_pause99_request_id_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for_get('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        $t->$method("$path?ACTION=request_id");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = %$default;
        $t->$method("$path?ACTION=request_id", \%form);
        # note $t->content;
    }
};

done_testing;
