use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;
use Test::Deep;
use Test::Differences;

my $default = {
    pause99_share_perms_makeco_m => [],
    pause99_share_perms_makeco_a => "TESTUSER2",
    SUBMIT_pause99_share_perms_makeco => 1,
};

Test::PAUSE::Web->setup;
Test::PAUSE::Web->reset_module_fixture;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=make_comaint");
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
                Module::User::Foo::Baz
            /]) or note explain \@modules;
        }
        # note $t->content;
    }
};

subtest 'normal case' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my @packages;
        if ($user eq 'TESTADMIN') {
            @packages = qw/Module::Admin::Bar/;
        }
        if ($user eq 'TESTUSER') {
            @packages = qw/Module::User::Bar/;
        }

        my %form = (
            %$default,
            pause99_share_perms_makeco_m => \@packages,
            pause99_share_perms_makeco_a => "TESTUSER4",
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=make_comaint", \%form);
        my @modules = map {$_->all_text} $t->dom->find('td.package')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        if ($user eq 'TESTADMIN') {
            cmp_set(\@modules, [qw/
                Module::Admin::Bar
                Module::Admin::Foo
            /]) or note explain \@modules;
            eq_or_diff(\@results, [
                'Added TESTUSER4 to co-maintainers of Module::Admin::Bar.',
            ]);
        }
        if ($user eq 'TESTUSER') {
            cmp_set(\@modules, [qw/
                Module::User::Bar
                Module::User::Foo
                Module::User::Foo::Baz
            /]) or note explain \@modules;
            eq_or_diff(\@results, [
                'Added TESTUSER4 to co-maintainers of Module::User::Bar.',
            ]);
        }
        note $t->content;
    }
};

subtest 'unknown user' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my @packages;
        if ($user eq 'TESTADMIN') {
            @packages = qw/Module::Admin::Bar/;
        }
        if ($user eq 'TESTUSER') {
            @packages = qw/Module::User::Bar/;
        }

        my %form = (
            %$default,
            pause99_share_perms_makeco_m => \@packages,
            pause99_share_perms_makeco_a => "UNKNOWN",
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=make_comaint", \%form);
        my @modules = map {$_->all_text} $t->dom->find('td.package')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        my @errors = map {$_->all_text} $t->dom->find('.error')->each;
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
        eq_or_diff(\@errors, [
            'UNKNOWN is not a valid userid.',
        ]);
        # note $t->content;
    }
};

subtest 'unrelated modules' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my %form = (
            %$default,
            pause99_share_perms_makeco_m => [qw/Module::Unrelated/],
            pause99_share_perms_makeco_a => "TESTUSER2",
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=make_comaint", \%form);
        my @modules = map {$_->all_text} $t->dom->find('td.package')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        my @errors = map {$_->all_text} $t->dom->find('.error')->each;
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
        eq_or_diff(\@errors, [
            'You do not seem to be maintainer of Module::Unrelated',
        ]);
        # note $t->content;
    }
};

done_testing;
