use Modern::Perl;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::PAUSE::Web;
use PAUSE::Web::Config;

Test::PAUSE::Web->setup;

for my $group (PAUSE::Web::Config->all_groups) {
    for my $name (PAUSE::Web::Config->action_names_for($group)) {
        my $action = PAUSE::Web::Config->action($name);
        say STDERR "# ACTION: $name ------------------------------------------------------------";
        my $t = Test::PAUSE::Web->new;
        if ($group eq "public") {
            $t->get_ok("/pause/query?ACTION=$name");
        } elsif ($group eq "user") {
            $t->user_get_ok("/pause/authenquery?ACTION=$name");
        } else {
            $t->admin_get_ok("/pause/authenquery?ACTION=$name");
        }
    }
}

done_testing;
