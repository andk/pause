use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use YAML::Syck ();

Test::PAUSE::Web->setup;

# SELECT user FROM grouptable WHERE ugroup='admin' order by user");
subtest 'get' => sub {
    Test::PAUSE::Web->authen_db->insert('grouptable', {
        user => "FOO",
        ugroup => "admin",
    });
    Test::PAUSE::Web->authen_db->insert('grouptable', {
        user => "BAR",
        ugroup => "admin",
    });
    Test::PAUSE::Web->authen_db->insert('grouptable', {
        user => "BAZ",
        ugroup => "bar",
    });

    for my $test (Test::PAUSE::Web->tests_for_get('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;

        $t->$method("$path?ACTION=who_admin")
          ->text_like('body', qr/Registered admins:\s+BAR, FOO/);

        $t->$method("$path?ACTION=who_admin&OF=YAML");
        my $list_amp = YAML::Syck::Load( $t->content );
        is_deeply( $list_amp, [qw/BAR FOO TESTADMIN/], "YAML output works" );

        $t->$method("$path?ACTION=who_admin;OF=YAML");
        my $list_sem = YAML::Syck::Load( $t->content );
        is_deeply( $list_sem, [qw/BAR FOO TESTADMIN/], "YAML output works" );
    }
};

done_testing;
