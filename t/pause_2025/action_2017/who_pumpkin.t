use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use YAML::Syck ();

Test::PAUSE::Web->setup;

# SELECT user FROM grouptable WHERE ugroup='pumpking' order by user");
subtest 'get' => sub {
    Test::PAUSE::Web->authen_db->insert('grouptable', {
        user => "FOO",
        ugroup => "pumpking",
    });
    Test::PAUSE::Web->authen_db->insert('grouptable', {
        user => "BAR",
        ugroup => "pumpking",
    });
    Test::PAUSE::Web->authen_db->insert('grouptable', {
        user => "BAZ",
        ugroup => "baz",
    });

    for my $test (Test::PAUSE::Web->tests_for('public')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        $t->get_ok("$path?ACTION=who_pumpkin")
          ->text_like("body", qr/Registered pumpkins:\s+BAR, FOO/);

        $t->get_ok("$path?ACTION=who_pumpkin&OF=YAML");
        my $list_amp = YAML::Syck::Load( $t->content );
        is_deeply( $list_amp, [qw/BAR FOO/], "YAML output works" );

    SKIP: {
        skip "; is not supported anymore", 1;
        $t->get_ok("$path?ACTION=who_pumpkin;OF=YAML");
        my $list_sem = YAML::Syck::Load( $t->content );
        is_deeply( $list_sem, [qw/BAR FOO/], "YAML output works" );
        }
    }
};

done_testing;
