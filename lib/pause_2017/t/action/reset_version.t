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
    for my $test (Test::PAUSE::Web->tests_for_get('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        $t->$method("$path?ACTION=reset_version");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for_post('user')) {
        my ($method, $path, $user) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;

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
        $t->$method("$path?ACTION=reset_version", \%form);
        # note $t->content;
    }
};

done_testing;
