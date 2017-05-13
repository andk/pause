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

subtest 'basic' => sub {
    my $t = Test::PAUSE::Web->new;

    $t->mod_dbh->do("TRUNCATE uris");

    # prepare distribution
    $t->user_post_ok("/pause/authenquery?ACTION=add_uri", {Content => $default_for_add_uri});

    my %form = %$default;
    $t->user_post_ok("/pause/authenquery?ACTION=edit_uris", {Content => \%form});
    note $t->content;
};

done_testing;
