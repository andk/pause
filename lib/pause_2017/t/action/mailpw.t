use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_mailpw_1 => "TESTUSER",
    pause99_mailpw_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'basic' => sub {
    my $t = Test::PAUSE::Web->new;
    my %form = %$default;
    $t->authen_dbh->do("TRUNCATE abrakadabra");
    $t->post_ok("/pause/query?ACTION=mailpw", {Content => \%form});
    note $t->content;
};

done_testing;
