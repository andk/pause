use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;
use Test::Deep;
use Test::Differences;

my $default = {
    pause99_remove_dist_comaint_tuples => [],
    SUBMIT_pause99_remove_dist_comaint => 1,
};

Test::PAUSE::Web->setup;
Test::PAUSE::Web->reset_module_fixture;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=remove_dist_comaint");
        my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        if ($user eq 'TESTADMIN') {
            cmp_set(\@dists, [qw/
                Module-Admin
            /]) or note explain \@dists;
        }
        if ($user eq 'TESTUSER') {
            cmp_set(\@dists, [qw/
                Module-User
            /]) or note explain \@dists;
        }
        # note $t->content;
    }
};

subtest 'normal case' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my @tuples;
        if ($user eq 'TESTADMIN') {
            @tuples = (
                'Module-Admin -- TESTUSER2',
            );
        }
        if ($user eq 'TESTUSER') {
            @tuples = (
                'Module-User -- TESTUSER2',
            );
        }

        my %form = (
            %$default,
            pause99_remove_dist_comaint_tuples => \@tuples,
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=remove_dist_comaint", \%form);
        my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        if ($user eq 'TESTADMIN') {
            cmp_set(\@dists, [qw/
            /]) or note explain \@dists;
            eq_or_diff(\@results, [
                'Removed TESTUSER2 from co-maintainers of Module::Admin::Bar (Module-Admin).',
                'Removed TESTUSER2 from co-maintainers of Module::Admin::Foo (Module-Admin).',
            ]);
        }
        if ($user eq 'TESTUSER') {
            cmp_set(\@dists, [qw/
                Module-User
            /]) or note explain \@dists;
            eq_or_diff(\@results, [
                'Removed TESTUSER2 from co-maintainers of Module::User::Bar (Module-User).',
                'Removed TESTUSER2 from co-maintainers of Module::User::Foo (Module-User).',
            ]);
        }
        # note $t->content;
    }
};

subtest 'broken tuple (not an owner)' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my %form = (
            %$default,
            pause99_remove_dist_comaint_tuples => ['Module-Unrelated -- TESTUSER2'],
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=remove_dist_comaint", \%form);
        my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        my @errors = map {$_->all_text} $t->dom->find('.error')->each;
        if ($user eq 'TESTADMIN') {
            cmp_set(\@dists, [qw/
                Module-Admin
            /]) or note explain \@dists;
        }
        if ($user eq 'TESTUSER') {
            cmp_set(\@dists, [qw/
                Module-User
            /]) or note explain \@dists;
        }
        ok !@results;
        eq_or_diff(\@errors, [
            'You do not seem to be owner of Module-Unrelated.',
        ]);
        # note $t->content;
    }
};

subtest 'broken tuple (not a comaint)' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my @tuples;
        if ($user eq 'TESTADMIN') {
            @tuples = (
                'Module-Admin -- TESTUSER4',
            );
        }
        if ($user eq 'TESTUSER') {
            @tuples = (
                'Module-User -- TESTUSER4',
            );

        }

        my %form = (
            %$default,
            pause99_remove_dist_comaint_tuples => \@tuples,
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=remove_dist_comaint", \%form);
        my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        my @errors = map {$_->all_text} $t->dom->find('.error')->each;
        if ($user eq 'TESTADMIN') {
            cmp_set(\@dists, [qw/
                Module-Admin
            /]) or note explain \@dists;
            eq_or_diff(\@errors, [
                'Cannot handle tuple Module-Admin -- TESTUSER4. If you believe, this is a bug, please complain.',
            ]);
        }
        if ($user eq 'TESTUSER') {
            cmp_set(\@dists, [qw/
                Module-User
            /]) or note explain \@dists;
            eq_or_diff(\@errors, [
                'Cannot handle tuple Module-User -- TESTUSER4. If you believe, this is a bug, please complain.',
            ]);
        }
        ok !@results;
        # note $t->content;
    }
};

done_testing;
