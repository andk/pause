use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_add_uri_httpupload => ["$Test::PAUSE::Web::AppRoot/htdocs/index.html", "index.html"],
    SUBMIT_pause99_add_uri_httpupload => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for_get('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        $t->$method("$path?ACTION=add_uri");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for_post('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = %$default;
        $t->$method("$path?ACTION=add_uri", \%form, "Content-Type" => "form-data");
        # note $t->content;
    }
};

done_testing;
