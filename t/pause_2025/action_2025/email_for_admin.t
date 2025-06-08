use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        $t->get_ok("/admin/email_for_admin")
          ->text_like("body", qr/TESTADMIN\s+testadmin\@localhost/)
          ->text_like("body", qr/TESTUSER\s+testuser\@localhost/);
        # note $t->content;

        $t->get_ok("/admin/email_for_admin?OF=YAML");
        my $list_amp = YAML::Syck::Load( $t->content );
        is_deeply( $list_amp, {
            TESTADMIN => 'testadmin@localhost',
            TESTCNSRD => 'testcnsrd@localhost',
            TESTUSER  => 'testuser@localhost',
            TESTUSER2 => 'testuser2@localhost',
            TESTUSER3 => 'testuser3@localhost',
            TESTUSER4 => 'testuser4@localhost',
        }, "YAML output works" );
        # note $t->content;
    }
};

done_testing;
