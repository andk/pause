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

{
    open my $fh, '>', $PAUSE::Config->{PAUSE_LOG};
    say $fh <<LOG;
pause log
pause log
pause log
LOG
}

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for_get('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        $t->user_get_ok("/pause/authenquery?ACTION=tail_logfile");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for_post('user')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;

        my %form = %$default;
        $t->$method("$path?ACTION=tail_logfile", \%form);
        # note $t->content;
    }
};

done_testing;
