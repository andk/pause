use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $mailing_list = {
    SUBMIT_pause99_add_user_Definitely => 1,
    pause99_add_user_userid => "MAILLIST",
    pause99_add_user_email => "ml\@localhost.localdomain",
    pause99_add_user_subscribe => "how to subscribe",
};

my $default = {
    HIDDENNAME => "TESTUSER",
    ACTIONREQ => "edit_ml",
    pause99_select_ml_action_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'basic' => sub {
    my $t = Test::PAUSE::Web->new;

    $t->admin_post_ok("/pause/authenquery?ACTION=add_user", $mailing_list);

    $t->mod_dbh->do("INSERT INTO list2user VALUE (?, ?)", undef, "MAILLIST", "TESTUSER");

    my %form = %$default;
    $t->admin_post_ok("/pause/authenquery?ACTION=select_ml_action", \%form);
    # note $t->content;
};

done_testing;
