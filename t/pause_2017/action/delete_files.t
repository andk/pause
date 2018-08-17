use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default_for_add_uri = {
    pause99_add_uri_httpupload => [Test::PAUSE::Web->file_to_upload],
    SUBMIT_pause99_add_uri_httpupload => 1,
};

my $default = {
    pause99_delete_files_FILE => ["T/TE/TESTUSER/Hash-RenameKey-0.02.tar.gz"],
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=delete_files");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        $t->mod_dbh->do("TRUNCATE uris");

        # prepare distribution
        $t->post_ok("$path?ACTION=add_uri", $default_for_add_uri, "Content-Type" => "form-data");

        $t->copy_to_authors_dir($user, scalar Test::PAUSE::Web->file_to_upload);

        my %form = %$default;
        $form{SUBMIT_pause99_delete_files_delete} = 1;
        $t->post_ok("$path?ACTION=delete_files", \%form);
        # note $t->content;
    }
};

done_testing;
