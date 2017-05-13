use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_change_passwd_pw1 => "new_pass",
    pause99_change_passwd_pw2 => "new_pass",
    pause99_change_passwd_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'basic' => sub {
    my $t = Test::PAUSE::Web->new;

    my %form = %$default;
    $t->user_post_ok("/pause/authenquery?ACTION=change_passwd", \%form);
    # note $t->content;
};

done_testing;
