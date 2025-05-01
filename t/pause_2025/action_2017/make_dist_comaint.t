use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;
use Test::Deep;
use Test::Differences;

my $default = {
    pause99_make_dist_comaint_d => [],
    pause99_make_dist_comaint_a => "TESTUSER2",
    SUBMIT_pause99_make_dist_comaint => 1,
};

Test::PAUSE::Web->setup;
Test::PAUSE::Web->reset_module_fixture;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=make_dist_comaint");
        my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        if ($user eq 'TESTADMIN') {
            cmp_set(\@dists, [qw/
                Module-Admin
            /]) or note explain \@dists;
        }
        if ($user eq 'TESTUSER') {
            cmp_set(\@dists, [qw/
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
        my $t = Test::PAUSE::Web->new(user => $user);

        my @dists;
        if ($user eq 'TESTADMIN') {
            @dists = qw/Module-Admin/;
        }
        if ($user eq 'TESTUSER') {
            @dists = qw/Module-User/;
        }

        my %form = (
            %$default,
            pause99_make_dist_comaint_d => \@dists,
            pause99_make_dist_comaint_a => "TESTUSER4",
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=make_dist_comaint", \%form);
        @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        if ($user eq 'TESTADMIN') {
            cmp_set(\@dists, [qw/
                Module-Admin
            /]) or note explain \@dists;
            eq_or_diff(\@results, [
                'Added TESTUSER4 to co-maintainers of Module::Admin::Bar (Module-Admin).',
                'Added TESTUSER4 to co-maintainers of Module::Admin::Foo (Module-Admin).',
            ]);
        }
        if ($user eq 'TESTUSER') {
            cmp_set(\@dists, [qw/
                Module-User
                Module-User-Foo-Baz
            /]) or note explain \@dists;
            eq_or_diff(\@results, [
                'Added TESTUSER4 to co-maintainers of Module::User::Bar (Module-User).',
                'Added TESTUSER4 to co-maintainers of Module::User::Foo (Module-User).',
            ]);
        }

        # note $t->content;
    }
};

subtest 'unknown user' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my @dists;
        if ($user eq 'TESTADMIN') {
            @dists = qw/Module-Admin/;
        }
        if ($user eq 'TESTUSER') {
            @dists = qw/Module-User/;
        }

        my %form = (
            %$default,
            pause99_make_dist_comaint_d => \@dists,
            pause99_make_dist_comaint_a => "UNKNOWN",
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=make_dist_comaint", \%form);
        @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
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
            'UNKNOWN is not a valid userid.',
        ]);
        # note $t->content;
    }
};

subtest 'unrelated dists' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my %form = (
            %$default,
            pause99_make_dist_comaint_d => [qw/Module-Unrelated/],
            pause99_make_dist_comaint_a => "TESTUSER2",
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=make_dist_comaint", \%form);
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
