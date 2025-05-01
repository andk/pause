use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_edit_cred_fullname => "new fullname",
    pause99_edit_cred_asciiname => "new ascii name",
    pause99_edit_cred_email => "new_email\@localhost.localdomain",
    pause99_edit_cred_homepage => "none",
    pause99_edit_cred_cpan_mail_alias => "none",
    pause99_edit_cred_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=edit_cred");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    plan skip_all => 'SKIP for now';
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my %form = %$default;
        $t->post_ok("$path?ACTION=edit_cred", \%form);
        # note $t->content;
    }
};

subtest 'post_with_token: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my %form = %$default;
        $t->post_with_token_ok("$path?ACTION=edit_cred", \%form);
        # note $t->content;
    }
};

subtest 'post_with_token: edit with CENSORED email' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        Test::PAUSE::Web->setup;
        $t->mod_db->update('users', { email => 'CENSORED' }, { userid => $user });
        my %form = (%$default, pause99_edit_cred_email => 'CENSORED');
        $t->post_with_token_ok("$path?ACTION=edit_cred", \%form);
        my @deliveries = $t->deliveries;
        like $deliveries[0]->as_string => qr/\[CENSORED\]/;
        # note $t->content;
    }
};

done_testing;
