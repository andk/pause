use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;
use Test::Deep;
use Test::Differences;

my $default = {
    pause99_share_perms_remocos_tuples => [],
    SUBMIT_pause99_share_perms_remocos => 1,
};

Test::PAUSE::Web->setup;
Test::PAUSE::Web->reset_module_fixture;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=remove_comaint");
        my @modules = map {$_->all_text} $t->dom->find('td.package')->each;
        if ($user eq 'TESTADMIN') {
            cmp_set(\@modules, [qw/
                Module::Admin::Bar
                Module::Admin::Foo
            /]) or note explain \@modules;
        }
        if ($user eq 'TESTUSER') {
            cmp_set(\@modules, [qw/
                Module::User::Bar
                Module::User::Foo
            /]) or note explain \@modules;
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
                'Module::Admin::Bar -- TESTUSER2',
            );
        }
        if ($user eq 'TESTUSER') {
            @tuples = (
                'Module::User::Bar -- TESTUSER2',
            );

        }

        my %form = (
            %$default,
            pause99_share_perms_remocos_tuples => \@tuples,
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=remove_comaint", \%form);
        my @modules = map {$_->all_text} $t->dom->find('td.package')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        if ($user eq 'TESTADMIN') {
            cmp_set(\@modules, [qw/
                Module::Admin::Foo
            /]) or note explain \@modules;
            eq_or_diff(\@results, [
                'Removed TESTUSER2 from co-maintainers of Module::Admin::Bar.',
            ]);
        }
        if ($user eq 'TESTUSER') {
            cmp_set(\@modules, [qw/
                Module::User::Foo
            /]) or note explain \@modules;
            eq_or_diff(\@results, [
                'Removed TESTUSER2 from co-maintainers of Module::User::Bar.',
            ]);
        }
        # note $t->content;
    }
};

subtest 'broken tuple (not the owner)' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my %form = (
            %$default,
            pause99_share_perms_remocos_tuples => ['Module::Unrelated -- TESTUSER2'],
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=remove_comaint", \%form);
        my @modules = map {$_->all_text} $t->dom->find('td.package')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        my @errors = map {$_->all_text} $t->dom->find('.error')->each;
        if ($user eq 'TESTADMIN') {
            cmp_set(\@modules, [qw/
                Module::Admin::Bar
                Module::Admin::Foo
            /]) or note explain \@modules;
        }
        if ($user eq 'TESTUSER') {
            cmp_set(\@modules, [qw/
                Module::User::Bar
                Module::User::Foo
            /]) or note explain \@modules;
        }
        ok !@results;
        eq_or_diff(\@errors, [
            'You do not seem to be owner of Module::Unrelated.',
        ]);
        # note $t->content;
    }
};

subtest 'broken tuple (not the comaint)' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my @tuples;
        if ($user eq 'TESTADMIN') {
            @tuples = (
                'Module::Admin::Bar -- TESTUSER4',
            );
        }
        if ($user eq 'TESTUSER') {
            @tuples = (
                'Module::User::Bar -- TESTUSER4',
            );

        }

        my %form = (
            %$default,
            pause99_share_perms_remocos_tuples => \@tuples,
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=remove_comaint", \%form);
        my @modules = map {$_->all_text} $t->dom->find('td.package')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        my @errors = map {$_->all_text} $t->dom->find('.error')->each;
        if ($user eq 'TESTADMIN') {
            cmp_set(\@modules, [qw/
                Module::Admin::Bar
                Module::Admin::Foo
            /]) or note explain \@modules;
            eq_or_diff(\@errors, [
                'Cannot handle tuple Module::Admin::Bar -- TESTUSER4. If you believe, this is a bug, please complain.' 
            ]);
        }
        if ($user eq 'TESTUSER') {
            cmp_set(\@modules, [qw/
                Module::User::Bar
                Module::User::Foo
            /]) or note explain \@modules;
            eq_or_diff(\@errors, [
                'Cannot handle tuple Module::User::Bar -- TESTUSER4. If you believe, this is a bug, please complain.' 
            ]);
        }
        ok !@results;
        # note $t->content;
    }
};

done_testing;
