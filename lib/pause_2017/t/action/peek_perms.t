use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_peek_perms_by => "TESTUSER",
    pause99_peek_perms_query => "a",
    pause99_peek_perms_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'basic' => sub {
    my $t = Test::PAUSE::Web->new;

    $t->mod_dbh->do("TRUNCATE primeur");
    my $sth = $t->mod_dbh->prepare("INSERT INTO primeur (package, userid) VALUES (?, ?)");
    $sth->execute("Foo", "TESTUSER");
    $sth->execute("Bar", "TESTUSER");

    my %form = %$default;
    $t->user_post_ok("/pause/authenquery?ACTION=peek_perms", {Content => \%form});
    note $t->content;
};

done_testing;
