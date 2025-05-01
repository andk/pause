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

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('public')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=mailpw");
        #note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for('public')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        my %form = %$default;
        $t->authen_dbh->do("TRUNCATE abrakadabra");
        my $res = $t->post("$path?ACTION=mailpw", \%form);
        ok !$res->is_success && $res->code == 403, "Forbidden";
        like $res->content => qr/Failed CSRF check/;
        # note $t->content;
    }
};

subtest 'post_with_token: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for('public')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        my %form = %$default;
        $t->authen_dbh->do("TRUNCATE abrakadabra");
        $t->post_with_token_ok("$path?ACTION=mailpw", \%form)
          ->text_like("p.form_response", qr/A token to change the password/);
        # note $t->content;
    }
};

subtest 'got an email instead of a userid' => sub {
    for my $test (Test::PAUSE::Web->tests_for('public')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        my %form = (
            %$default,
            pause99_mailpw_1 => 'INV@LID',
        );
        $t->authen_dbh->do("TRUNCATE abrakadabra");
        $t->post_with_token_ok("$path?ACTION=mailpw", \%form)
          ->text_is('h2', 'Error')
          ->text_like('p.error_message', qr/Please supply a userid/s);
    }
};

subtest 'invalid userid' => sub {
    for my $test (Test::PAUSE::Web->tests_for('public')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        my %form = (
            %$default,
            pause99_mailpw_1 => 'INV#LID',
        );
        $t->authen_dbh->do("TRUNCATE abrakadabra");
        $t->post_with_token_ok("$path?ACTION=mailpw", \%form)
          ->text_is('h2', 'Error')
          ->text_like('p.error_message', qr/A userid of INV#LID is not allowed/s);
    }
};

subtest 'cannot find a userid' => sub {
    for my $test (Test::PAUSE::Web->tests_for('public')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        my %form = (
            %$default,
            pause99_mailpw_1 => 'NOTFOUND',
        );
        $t->authen_dbh->do("TRUNCATE abrakadabra");
        $t->post_with_token_ok("$path?ACTION=mailpw", \%form)
          ->text_is('h2', 'Error')
          ->text_like('p.error_message', qr/Cannot find a userid.+NOTFOUND/s);
        # note $t->content;
    }
};

subtest 'no secretmail' => sub {
    for my $test (Test::PAUSE::Web->tests_for('public')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        my %form = (
            %$default,
        );
        $t->authen_dbh->do("TRUNCATE abrakadabra");
        $t->authen_db->update('usertable', {secretemail => undef}, {user => "TESTUSER"});
        $t->post_with_token_ok("$path?ACTION=mailpw", \%form)
          ->text_like("p.form_response", qr/A token to change the password/);
        # note $t->content;
    }

    Test::PAUSE::Web->setup; # restore the original state
};

subtest 'requested recently' => sub {
    for my $test (Test::PAUSE::Web->tests_for('public')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        my %form = %$default;
        $t->authen_dbh->do("TRUNCATE abrakadabra");
        $t->post_with_token_ok("$path?ACTION=mailpw", \%form)
          ->text_like("p.form_response", qr/A token to change the password/);
        $t->post_with_token_ok("$path?ACTION=mailpw", \%form)
          ->text_is('h2', 'Error')
          ->text_like('p.error_message', qr/A token for TESTUSER that allows/s);
        # note $t->content;
    }
};

subtest 'user without an entry in usertable: has email' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        my %form = (
          %$default,
          pause99_mailpw_1 => "OTHERUSER",
        );
        $t->authen_dbh->do("TRUNCATE abrakadabra");
        $t->mod_db->insert('users', {
            userid => 'OTHERUSER',
            email  => 'foo@localhost',
        }, {replace => 1});
        $t->authen_db->delete('usertable', {user => 'OTHERUSER'});
        ok !@{ $t->authen_db->select('usertable', ['user'], {user => 'OTHERUSER'}) // [] };
        $t->post_with_token_ok("$path?ACTION=mailpw", \%form)
          ->text_like("p.form_response", qr/A token to change the password/);

        # new usertable entry is created
        ok @{ $t->authen_db->select('usertable', ['user'], {user => 'OTHERUSER'}) // [] };
        #note $t->content;
    }
};

subtest 'user without an entry in usertable: without email' => sub {
    for my $test (Test::PAUSE::Web->tests_for('admin')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        my %form = (
          %$default,
          pause99_mailpw_1 => "OTHERUSER",
        );
        $t->authen_dbh->do("TRUNCATE abrakadabra");
        $t->mod_db->insert('users', {
            userid => 'OTHERUSER',
            email  => '',
        }, {replace => 1});
        $t->authen_db->delete('usertable', {user => 'OTHERUSER'});
        ok !@{ $t->authen_db->select('usertable', ['user'], {user => 'OTHERUSER'}) // [] };
        $t->post_with_token_ok("$path?ACTION=mailpw", \%form)
          ->text_is('h2', 'Error')
          ->text_like('p.error_message', qr/A userid of OTHERUSER\s+is not known/s);

        # new usertable entry is not created
        ok !@{ $t->authen_db->select('usertable', ['user'], {user => 'OTHERUSER'}) // [] };
        #note $t->content;
    }
};

done_testing;
