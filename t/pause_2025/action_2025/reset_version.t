use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_reset_version_PKG => ["Foo"],
    SUBMIT_pause99_reset_version_forget => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        $t->get_ok("/user/reset_version");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        $t->mod_dbh->do("TRUNCATE packages");
        $t->mod_db->insert('packages', {
            package => "Foo",
            version => "0.01",
            dist => "T/TE/$user/Foo-0.01.tar.gz",
            file => "Foo-0.01.tar.gz",
        });
        $t->mod_db->insert('packages', {
            package => "Bar",
            version => "0.02",
            dist => "T/TE/$user/Bar-0.02.tar.gz",
            file => "Bar-0.02.tar.gz",
        });

        my %form = %$default;
        $t->post_ok("/user/reset_version", \%form);
        # note $t->content;
    }
};

done_testing;
