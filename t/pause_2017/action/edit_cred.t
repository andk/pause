use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_edit_cred_fullname => "new fullname",
    pause99_edit_cred_asciiname => "new ascii name",
    pause99_edit_cred_email => "new_email\@localhost.localdomain",
    pause99_edit_cred_homepage => "none",
    pause99_edit_cred_cpan_mail_alias => "none",
    pause99_edit_cred_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for_get('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        $t->$method("$path?ACTION=edit_cred");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    plan skip_all => 'SKIP for now';
    for my $test (Test::PAUSE::Web->tests_for_post('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;

        my %form = %$default;
        $t->$method("$path?ACTION=edit_cred", \%form);
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for_safe_post('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;

        my %form = %$default;
        $t->$method("$path?ACTION=edit_cred", \%form);
        # note $t->content;
    }
};

done_testing;
