use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;
use Test::Deep;
use Test::Differences;

my $default = {
    pause99_giveup_dist_comaint_d => "Module-Comaint",
    SUBMIT_pause99_giveup_dist_comaint => 1,
};

Test::PAUSE::Web->setup;
Test::PAUSE::Web->reset_module_fixture;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;

        Test::PAUSE::Web->reset_module_fixture;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        $t->get_ok("/user/giveup_dist_comaint");
        my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@dists, [qw/
                Module-Comaint
                Module-User
            /]) or note explain \@dists;
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@dists, [qw/
                Module-Comaint
            /]) or note explain \@dists;
        }
        # note $t->content;
    }
};

subtest 'normal case (comaint)' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        my %form = (
            %$default,
            pause99_giveup_dist_comaint_d => [qw/Module-Comaint/],
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("/user/giveup_dist_comaint", \%form);
        my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@dists, [qw/
                Module-User
            /]) or note explain \@dists;
            eq_or_diff(\@results, [
                'Removed TESTADMIN from co-maintainers of Module::Comaint (Module-Comaint).',
                'Removed TESTADMIN from co-maintainers of Module::Comaint::Foo (Module-Comaint).',
            ]);
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@dists, [qw/
            /]) or note explain \@dists;
            eq_or_diff(\@results, [
                'Removed TESTUSER from co-maintainers of Module::Comaint (Module-Comaint).',
                'Removed TESTUSER from co-maintainers of Module::Comaint::Foo (Module-Comaint).',
            ]);
        }
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
            pause99_giveup_dist_comaint_d => [qw/Module-Unrelated/],
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("/user/giveup_dist_comaint", \%form);
        my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        my @errors = map {$_->all_text} $t->dom->find('.error')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@dists, [qw/
                Module-Comaint
                Module-User
            /]) or note explain \@dists;
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@dists, [qw/
                Module-Comaint
            /]) or note explain \@dists;
        }
        ok !@results;
        eq_or_diff(\@errors, [
            'You do not seem to be co-maintainer of Module-Unrelated'
        ]) or note explain \@errors;
        # note $t->content;
    }
};

done_testing;
