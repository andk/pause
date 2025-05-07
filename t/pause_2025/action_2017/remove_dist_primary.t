use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;
use Test::Deep;
use Test::Differences;

my $default = {
    pause99_remove_dist_primary_d => [],
    SUBMIT_pause99_remove_dist_primary => 1,
};

Test::PAUSE::Web->setup;
Test::PAUSE::Web->reset_module_fixture;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;

        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=remove_dist_primary");
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
            pause99_remove_dist_primary_d => \@dists,
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=remove_dist_primary", \%form);
        @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@dists, [qw/
            /]) or note explain \@dists;
            eq_or_diff(\@results, [
                'Removed primary maintainership of TESTADMIN from Module::Admin::Bar (Module-Admin).',
                'Removed primary maintainership of TESTADMIN from Module::Admin::Foo (Module-Admin).',
            ]);

            # really transferred to ADOPTME?
            $t->get_ok("$path?ACTION=peek_dist_perms", {
                pause99_peek_dist_perms_query => "ADOPTME",
                pause99_peek_dist_perms_by => "a",
                pause99_peek_dist_perms_sub => 1,
            });
            my @adoptme_dists = map {$_->all_text} $t->dom->find('td.dist')->each;
            cmp_set(\@adoptme_dists, [qw/Module-Admin/]) or note explain \@adoptme_dists;
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@dists, [qw/
                Module-User-Foo-Baz
            /]) or note explain \@dists;
            eq_or_diff(\@results, [
                'Removed primary maintainership of TESTUSER from Module::User::Bar (Module-User).',
                'Removed primary maintainership of TESTUSER from Module::User::Foo (Module-User).',
            ]);

            # really transferred to ADOPTME?
            $t->get_ok("$path?ACTION=peek_dist_perms", {
                pause99_peek_dist_perms_query => "ADOPTME",
                pause99_peek_dist_perms_by => "a",
                pause99_peek_dist_perms_sub => 1,
            });
            my @adoptme_dists = map {$_->all_text} $t->dom->find('td.dist')->each;
            cmp_set(\@adoptme_dists, [qw/Module-User/]) or note explain \@adoptme_dists;
        }
        # note $t->content;
    }
};

subtest 'unrelated dists' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my %form = (
            %$default,
            pause99_remove_dist_primary_d => [qw/Module-Unrelated/],
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=remove_dist_primary", \%form);
        my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        my @warnings = map {$_->all_text} $t->dom->find('.warning')->each;
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
        eq_or_diff(\@warnings, [
            'You need to select one or more distributions. Nothing done.',
        ]);
        # note $t->content;
    }
};

done_testing;
