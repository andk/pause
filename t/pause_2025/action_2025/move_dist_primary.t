use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;
use Test::Deep;
use Test::Differences;

my $default = {
    pause99_move_dist_primary_d => [],
    pause99_move_dist_primary_a => "TESTUSER2",
    SUBMIT_pause99_move_dist_primary => 1,
};

Test::PAUSE::Web->setup;
Test::PAUSE::Web->reset_module_fixture;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        $t->get_ok("/user/move_dist_primary");
        my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@dists, [qw/
                Module-Admin
            /]) or note explain \@dists;
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@dists, [qw/
                Module-User
                Module-User-Foo-Baz
            /]) or note explain \@dists;
        }
        # note $t->content;
    }
};

subtest 'normal case' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        my @dists;
        if ($user eq 'TESTADMIN') {
            @dists = qw/Module-Admin/;
        }
        if ($user eq 'TESTUSER') {
            @dists = qw/Module-User/;
        }

        my %form = (
            %$default,
            pause99_move_dist_primary_d => \@dists,
            pause99_move_dist_primary_a => "TESTUSER2",
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("/user/move_dist_primary", \%form);
        @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@dists, [qw/
            /]) or note explain \@dists;
            eq_or_diff(\@results, [
                'Made TESTUSER2 primary maintainer of Module::Admin::Bar (Module-Admin).',
                'Made TESTUSER2 primary maintainer of Module::Admin::Foo (Module-Admin).',
            ]);
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@dists, [qw/
                Module-User-Foo-Baz
            /]) or note explain \@dists;
            eq_or_diff(\@results, [
                'Made TESTUSER2 primary maintainer of Module::User::Bar (Module-User).',
                'Made TESTUSER2 primary maintainer of Module::User::Foo (Module-User).',
            ]);
        }
        note $t->content;
    }
};

subtest 'unknown user' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        my @dists;
        if ($user eq 'TESTADMIN') {
            @dists = qw/Module-Admin/;
        }
        if ($user eq 'TESTUSER') {
            @dists = qw/Module-User/;
        }

        my %form = (
            %$default,
            pause99_move_dist_primary_d => \@dists,
            pause99_move_dist_primary_a => "UNKNOWN",
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("/user/move_dist_primary", \%form);
        my @new_dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        my @errors = map {$_->all_text} $t->dom->find('.error')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@new_dists, [qw/
                Module-Admin
            /]) or note explain \@dists;
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@new_dists, [qw/
                Module-User
                Module-User-Foo-Baz
            /]) or note explain \@dists;
        }
        ok !@results;
        eq_or_diff(\@errors, [
            'UNKNOWN is not a valid userid.',
        ]);
        # note $t->content;
    }
};

subtest 'unrelated dists' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        my %form = (
            %$default,
            pause99_move_dist_primary_d => [qw/Module-Unrelated/],
            pause99_move_dist_primary_a => "TESTUSER2",
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("/user/move_dist_primary", \%form);
        my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        my @errors = map {$_->all_text} $t->dom->find('.error')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@dists, [qw/
                Module-Admin
            /]) or note explain \@dists;
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@dists, [qw/
                Module-User
                Module-User-Foo-Baz
            /]) or note explain \@dists;
        }
        ok !@results;
        eq_or_diff(\@errors, [
            'You do not seem to be maintainer of Module-Unrelated',
        ]);
        # note $t->content;
    }
};

done_testing;
