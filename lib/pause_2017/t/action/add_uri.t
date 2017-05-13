use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_add_uri_httpupload => ["$Test::PAUSE::Web::AppRoot/htdocs/index.html", "index.html"],
    SUBMIT_pause99_add_uri_httpupload => 1,
};

Test::PAUSE::Web->setup;

subtest 'basic' => sub {
    my $t = Test::PAUSE::Web->new;
    my %form = %$default;
    $t->user_post_ok("/pause/authenquery?ACTION=add_uri", {Content => \%form, Header => {"Content-Type" => "form-data"}});
    note $t->content;
};

done_testing;
