use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_peek_perms_by => "TESTUSER",
    pause99_peek_perms_query => "a",
    pause99_peek_perms_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for_get('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        $t->$method("$path?ACTION=peek_perms");
        # note $t->content;
    }
};

#subtest 'post: basic' => sub {
{
    for my $test (Test::PAUSE::Web->tests_for_post('user')) {
        my ($method, $path, $user) = @$test;
        note "$method for $path";

        my $t = Test::PAUSE::Web->new;

        $t->mod_dbh->do("TRUNCATE primeur");
        $t->mod_db->insert("primeur", {
            package => "Foo",
            userid => $user,
        });
        $t->mod_db->insert("primeur", {
            package => "Bar",
            userid => $user,
        });

        my %form = (
            %$default,
            pause99_peek_perms_by => $user,
        );
        $t->$method("$path?ACTION=peek_perms", \%form);
        # note $t->content;
    }
};

done_testing;
