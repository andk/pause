use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_mailpw_1 => "TESTUSER",
    pause99_mailpw_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for_get('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        $t->$method("$path?ACTION=mailpw");
        #note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = %$default;
        $t->authen_dbh->do("TRUNCATE abrakadabra");
        $t->$method("$path?ACTION=mailpw", \%form);
        # note $t->content;
    }
};

done_testing;
