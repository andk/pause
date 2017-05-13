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

subtest 'basic' => sub {
    my $t = Test::PAUSE::Web->new;

    $t->mod_dbh->do("TRUNCATE uris");

    # prepare distribution
    $t->user_post_ok("/pause/authenquery?ACTION=add_uri", {Content => $default_for_add_uri});

    $t->copy_to_authors_dir("TESTUSER", scalar Test::PAUSE::Web->file_to_upload);

    my %form = %$default;
    $form{SUBMIT_pause99_delete_files_delete} = 1;
    $t->user_post_ok("/pause/authenquery?ACTION=delete_files", {Content => \%form});
    note $t->content;
};

done_testing;
