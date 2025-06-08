use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;
use Test::Deep;
use Test::Differences;

my $default = {
    pause99_share_perms_pr_m => [],
    SUBMIT_pause99_share_perms_remopr => 1,
};

Test::PAUSE::Web->setup;
Test::PAUSE::Web->reset_module_fixture;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;

        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        $t->get_ok("/user/remove_primary");
        my @modules = map {$_->all_text} $t->dom->find('td.package')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@modules, [qw/
                Module::Admin::Bar
                Module::Admin::Foo
            /]) or note explain \@modules;
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@modules, [qw/
                Module::User::Bar
                Module::User::Foo
                Module::User::Foo::Baz
            /]) or note explain \@modules;
        }
        # note $t->content;
    }
};

subtest 'normal case' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        my @packages;
        if ($user eq 'TESTADMIN') {
            @packages = qw/Module::Admin::Bar/;
        }
        if ($user eq 'TESTUSER') {
            @packages = qw/Module::User::Bar/;
        }

        my %form = (
            %$default,
            pause99_share_perms_pr_m => \@packages,
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("/user/remove_primary", \%form);
        my @modules = map {$_->all_text} $t->dom->find('td.package')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@modules, [qw/
                Module::Admin::Foo
            /]) or note explain \@modules;
            eq_or_diff(\@results, [
                'Removed primary maintainership of TESTADMIN from Module::Admin::Bar.',
            ]);

            # really transferred to ADOPTME?
            $t->get_ok("/user/peek_perms", {
                pause99_peek_perms_query => "ADOPTME",
                pause99_peek_perms_by => "a",
                pause99_peek_perms_sub => 1,
            });
            my @adoptme_modules = map {$_->all_text} $t->dom->find('td.module')->each;
            cmp_set(\@adoptme_modules, [qw/Module::Admin::Bar/]) or note explain \@adoptme_modules;
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@modules, [qw/
                Module::User::Foo
                Module::User::Foo::Baz
            /]) or note explain \@modules;
            eq_or_diff(\@results, [
                'Removed primary maintainership of TESTUSER from Module::User::Bar.',
            ]);

            # really transferred to ADOPTME?
            $t->get_ok("/user/peek_perms", {
                pause99_peek_perms_query => "ADOPTME",
                pause99_peek_perms_by => "a",
                pause99_peek_perms_sub => 1,
            });
            my @adoptme_modules = map {$_->all_text} $t->dom->find('td.module')->each;
            cmp_set(\@adoptme_modules, [qw/Module::User::Bar/]) or note explain \@adoptme_modules;
        }
        # note $t->content;
    }
};

subtest 'unrelated modules' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        my %form = (
            %$default,
            pause99_share_perms_pr_m => [qw/Module::Unrelated/],
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("/user/remove_primary", \%form);
        my @modules = map {$_->all_text} $t->dom->find('td.package')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        my @warnings = map {$_->all_text} $t->dom->find('.warning')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@modules, [qw/
                Module::Admin::Bar
                Module::Admin::Foo
            /]) or note explain \@modules;
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@modules, [qw/
                Module::User::Bar
                Module::User::Foo
                Module::User::Foo::Baz
            /]) or note explain \@modules;
        }
        ok !@results;
        eq_or_diff(\@warnings, [
            'You need to select one or more packages. Nothing done.',
        ]);
        # note $t->content;
    }
};

done_testing;
