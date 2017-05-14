use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_tail_logfile_1 => 5000,
    pause99_tail_logfile_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'basic' => sub {
    my $t = Test::PAUSE::Web->new;

    open my $fh, '>', $PAUSE::Config->{PAUSE_LOG};
    say $fh <<LOG;
pause log
pause log
pause log
LOG

    my %form = %$default;
    $t->user_post_ok("/pause/authenquery?ACTION=tail_logfile", \%form);
    note $t->content;
};

done_testing;
