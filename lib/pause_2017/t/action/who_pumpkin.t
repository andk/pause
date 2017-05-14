use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use YAML::Syck ();

Test::PAUSE::Web->setup;

# SELECT user FROM grouptable WHERE ugroup='pumpking' order by user");
subtest 'basic' => sub {
    my $t = Test::PAUSE::Web->new;

    $t->authen_dbh->do( "INSERT INTO grouptable (user, ugroup) VALUE (?, ?)",
        undef, "FOO", "pumpking" );
    $t->authen_dbh->do( "INSERT INTO grouptable (user, ugroup) VALUE (?, ?)",
        undef, "BAR", "pumpking" );
    $t->authen_dbh->do( "INSERT INTO grouptable (user, ugroup) VALUE (?, ?)",
        undef, "BAZ", "baz" );

    $t->get_ok('/pause/query?ACTION=who_pumpkin');
    like(
        $t->content,
        qr/Registered pumpkins: BAR, FOO/,
        'Found expected pumpkins'
    );

    $t->get_ok('/pause/query?ACTION=who_pumpkin&OF=YAML');
    my $list_amp = YAML::Syck::Load( $t->content );
    is_deeply( $list_amp, [qw/BAR FOO/], "YAML output works" );

    $t->get_ok('/pause/query?ACTION=who_pumpkin;OF=YAML');
    my $list_sem = YAML::Syck::Load( $t->content );
    is_deeply( $list_sem, [qw/BAR FOO/], "YAML output works" );
};

done_testing;
