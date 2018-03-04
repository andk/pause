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
    pause99_reindex_FILE => ["Hash-RemoteKey-0.02.tar.gz"],
    SUBMIT_pause99_reindex_delete => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for_get('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        $t->$method("$path?ACTION=reindex");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for_post('user')) {
        my ($method, $path, $user) = @$test;
        note "$method for $path";

        my $t = Test::PAUSE::Web->new;

        $t->mod_dbh->do("TRUNCATE uris");

        # prepare distribution
        $t->$method("$path?ACTION=add_uri", $default_for_add_uri, "Content-Type" => "form-data");

        $t->copy_to_authors_dir($user, scalar Test::PAUSE::Web->file_to_upload);

        my %form = %$default;
        $t->$method("$path?ACTION=reindex", \%form);
        # note $t->content;
    }
};

done_testing;
