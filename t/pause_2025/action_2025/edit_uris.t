use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default_for_add_uri = {
    pause99_add_uri_httpupload => ["$Test::PAUSE::Web::AppRoot/t/staging/Hash-RenameKey-0.02.tar.gz", "Hash-RenameKey-0.02.tar.gz"],
    SUBMIT_pause99_add_uri_httpupload => 1,
};

my $default = {
    pause99_edit_uris_3 => "T/TE/TESTUSER/Hash-RenameKey-0.02.tar.gz",
    pause99_edit_uris_2 => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        $t->get_ok("/user/edit_uris");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        $t->mod_dbh->do("TRUNCATE uris");

        # prepare distribution
        $t->post_ok("/user/add_uri", $default_for_add_uri, "Content-Type" => "form-data");

        my %form = %$default;
        $form{pause99_edit_uris_3} =~ s/TESTUSER/$user/;
        $t->post_ok("/user/edit_uris", \%form);
        # note $t->content;
    }
};

done_testing;
