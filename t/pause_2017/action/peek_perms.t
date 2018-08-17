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
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=peek_perms");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;

        my $t = Test::PAUSE::Web->new(user => $user);

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
        $t->post_ok("$path?ACTION=peek_perms", \%form);
        # note $t->content;
    }
};

done_testing;
