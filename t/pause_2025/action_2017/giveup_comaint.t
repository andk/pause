use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;
use Test::Deep;
use Test::Differences;

my $default = {
    pause99_share_perms_remome_m => "Module::Comaint",
    SUBMIT_pause99_share_perms_remome => 1,
};

Test::PAUSE::Web->setup;
Test::PAUSE::Web->reset_module_fixture;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;

        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=giveup_comaint");
        my @modules = map {$_->all_text} $t->dom->find('td.package')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@modules, [qw/
                Module::Comaint
                Module::Comaint::Foo
                Module::User::Foo
            /]) or note explain \@modules;
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@modules, [qw/
                Module::Comaint
                Module::Comaint::Foo
            /]) or note explain \@modules;
        }
        # note $t->content;
    }
};

subtest 'normal case (comaint)' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my %form = (
            %$default,
            pause99_share_perms_remome_m => [qw/Module::Comaint Module::Comaint::Foo/],
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=giveup_comaint", \%form);
        my @modules = map {$_->all_text} $t->dom->find('td.package')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@modules, [qw/
                Module::User::Foo
            /]) or note explain \@modules;
            eq_or_diff(\@results, [
                'Removed TESTADMIN from co-maintainers of Module::Comaint.',
                'Removed TESTADMIN from co-maintainers of Module::Comaint::Foo.',
            ]);
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@modules, [qw/
            /]) or note explain \@modules;
            eq_or_diff(\@results, [
                'Removed TESTUSER from co-maintainers of Module::Comaint.',
                'Removed TESTUSER from co-maintainers of Module::Comaint::Foo.',
            ]);
        }
        # note $t->content;
    }
};

subtest 'unrelated modules' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);

        my %form = (
            %$default,
            pause99_share_perms_remome_m => [qw/Module::Unrelated Module::Unrelated::Foo/],
        );

        Test::PAUSE::Web->reset_module_fixture;
        $t->post_ok("$path?ACTION=giveup_comaint", \%form);
        my @modules = map {$_->all_text} $t->dom->find('td.package')->each;
        my @results = map {$_->all_text} $t->dom->find('.result')->each;
        my @errors = map {$_->all_text} $t->dom->find('.error')->each;
        if ($user eq 'TESTADMIN') {
            cmp_bag(\@modules, [qw/
                Module::Comaint
                Module::Comaint::Foo
                Module::User::Foo
            /]) or note explain \@modules;
        }
        if ($user eq 'TESTUSER') {
            cmp_bag(\@modules, [qw/
                Module::Comaint
                Module::Comaint::Foo
            /]) or note explain \@modules;
        }
        ok !@results;
        eq_or_diff(\@errors, [
            'You do not seem to be co-maintainer of Module::Unrelated'
        ]) or note explain \@errors;
        # note $t->content;
    }
};

done_testing;
