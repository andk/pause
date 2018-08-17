use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use Time::Piece;
use utf8;

my $default = {
    pause99_change_passwd_pw1 => "new_pass",
    pause99_change_passwd_pw2 => "new_pass",
    pause99_change_passwd_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=change_passwd");
        # note $t->content;
    }
};

subtest 'get: public with ABRA' => sub {
    for my $test (Test::PAUSE::Web->tests_for('public')) {
        my ($path, $user) = @$test;
        next if $user; # public only
        my $t = Test::PAUSE::Web->new(user => $user);

        my $chuser = 'TESTUSER';
        my $chpass = 'testpassword';
        $t->authen_dbh->do('TRUNCATE abrakadabra');
        ok $t->authen_db->insert('abrakadabra', {
            user => $chuser,
            chpasswd => $chpass,
            expires => Time::Piece->new(time + 3600)->strftime('%Y-%m-%d %H:%M:%S'),
        });

        $t->get_ok("$path?ACTION=change_passwd&ABRA=$chuser.$chpass");
        # note $t->content;

        # No links should keep ABRA (71a745d)
        my @links = map {$_->attr('href')} $t->dom->at('a');
        ok !grep {$_ =~ /ABRA=/} @links;
    }
};

subtest 'post: basic' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my %form = %$default;
        my $t = Test::PAUSE::Web->new(user => $user);
        my $res = $t->post("$path?ACTION=change_passwd", \%form);
        ok !$res->is_success && $res->code == 403, "Forbidden";
        like $res->content => qr/Failed CSRF check/;
        # note $t->content;
    }
};

subtest 'post_with_token: basic' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my %form = %$default;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->post_with_token_ok("$path?ACTION=change_passwd", \%form)
          ->text_like("p.password_stored", qr/New password stored/);
        is $t->deliveries => 1, "one delivery for admin";
        # note $t->content;
    }
};

subtest 'post_with_token: public with ABRA' => sub {
    for my $test (Test::PAUSE::Web->tests_for('public')) {
        my ($path, $user) = @$test;
        next if $user; # public only
        my $t = Test::PAUSE::Web->new(user => $user);

        my $chuser = 'TESTUSER';
        my $chpass = 'testpassword';
        $t->authen_dbh->do('TRUNCATE abrakadabra');
        ok $t->authen_db->insert('abrakadabra', {
            user => $chuser,
            chpasswd => $chpass,
            expires => Time::Piece->new(time + 3600)->strftime('%Y-%m-%d %H:%M:%S'),
        });

        my %form = %$default;
        $t->post_with_token_ok("$path?ACTION=change_passwd&ABRA=$chuser.$chpass", \%form);
        $t->text_like("p.password_stored", qr/New password stored/);
        # note $t->content;

        # No links should keep ABRA (71a745d)
        my @links = map {$_->attr('href')} $t->dom->at('a');
        ok !grep {$_ =~ /ABRA=/} @links;
    }
};

subtest 'post_with_token: passwords mismatch' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        my %form = (
            %$default,
            pause99_change_passwd_pw2 => "wrong_pass",
        );
        $t->post_with_token_ok("$path?ACTION=change_passwd", \%form)
          ->text_is("h2", "Error")
          ->text_like("p.error_message", qr/The two passwords didn't match./);
        ok !$t->deliveries, "no delivery for admin";
        # note $t->content;
    }
};

subtest 'post_with_token: only one password' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        my %form = (
            %$default,
            pause99_change_passwd_pw2 => undef,
        );
        $t->post_with_token_ok("$path?ACTION=change_passwd", \%form)
          ->text_is("h2", "Error")
          ->text_like("p.error_message", qr/You need to fill in the same password in both fields./);
        ok !$t->deliveries, "no delivery for admin";
        # note $t->content;
    }
};

subtest 'post_with_token: no password' => sub {
    Test::PAUSE::Web->setup;
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        my %form = (
            %$default,
            pause99_change_passwd_pw1 => undef,
            pause99_change_passwd_pw2 => undef,
        );
        $t->post_with_token_ok("$path?ACTION=change_passwd", \%form)
          ->text_is("h2", "Error")
          ->text_like("p.error_message", qr/Please fill in the form with passwords./);
        ok !$t->deliveries, "no delivery for admin";
        # note $t->content;
    }
};

done_testing;
