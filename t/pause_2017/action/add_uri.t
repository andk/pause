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
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=add_uri");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        my %form = %$default;
        $t->post_ok("$path?ACTION=add_uri", \%form, "Content-Type" => "form-data");
        # note $t->content;
    }
};

done_testing;
