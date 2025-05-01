use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;
use YAML::Syck;
use Test::Deep;
use Test::Differences;

my $default = {
    pause99_peek_perms_query => "TESTUSER",
    pause99_peek_perms_by => "a",
    pause99_peek_perms_sub => 1,
};

Test::PAUSE::Web->setup;
Test::PAUSE::Web->reset_module_fixture;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=peek_perms");
        # note $t->content;
    }
};

subtest 'search by author' => sub {
    for my $method (qw/get_ok post_ok/) {
        for my $test (Test::PAUSE::Web->tests_for('user')) {
            my ($path, $user) = @$test;

            my $t = Test::PAUSE::Web->new(user => $user);

            my %form = (
                %$default,
                pause99_peek_perms_query => $user,
            );
            $t->$method("$path?ACTION=peek_perms", \%form);
            my @modules = map {$_->all_text} $t->dom->find('td.module')->each;
            my @types   = map {$_->all_text} $t->dom->find('td.type')->each;
            if ($user eq 'TESTADMIN') {
                cmp_bag(\@modules, [qw/
                    Module::Admin::Bar
                    Module::Admin::Foo
                    Module::Comaint
                    Module::Comaint::Foo
                    Module::User::Foo
                /]) or note explain \@modules;
                ok grep(/co-maint/, @types), 'Has co-maint';
            }
            if ($user eq 'TESTUSER') {
                cmp_bag(\@modules, [qw/
                    Module::Comaint
                    Module::Comaint::Foo
                    Module::User::Bar
                    Module::User::Foo
                    Module::User::Foo::Baz
                /]) or note explain \@modules;
                ok grep(/co-maint/, @types), 'No co-maint';
            }
            # note $t->content;

            $t->$method("$path?ACTION=peek_perms&OF=YAML", \%form);
            my $list = YAML::Syck::Load( $t->content );
            if ($user eq 'TESTADMIN') {
                eq_or_diff( $list => [
                   {
                     'module' => 'Module::Admin::Bar',
                     'owner' => 'TESTADMIN',
                     'type' => 'first-come',
                     'userid' => 'TESTADMIN'
                   },
                   {
                     'module' => 'Module::Admin::Foo',
                     'owner' => 'TESTADMIN',
                     'type' => 'first-come',
                     'userid' => 'TESTADMIN'
                   },
                   {
                     'module' => 'Module::User::Foo',
                     'owner' => 'TESTUSER',
                     'type' => 'co-maint',
                     'userid' => 'TESTADMIN'
                   },
                   {
                     'module' => 'Module::Comaint',
                     'owner' => 'TESTUSER2',
                     'type' => 'co-maint',
                     'userid' => 'TESTADMIN'
                   },
                   {
                     'module' => 'Module::Comaint::Foo',
                     'owner' => 'TESTUSER2',
                     'type' => 'co-maint',
                     'userid' => 'TESTADMIN'
                   },
                ] );
            }
            if ($user eq 'TESTUSER') {
                eq_or_diff( $list => [
                   {
                     'module' => 'Module::User::Bar',
                     'owner' => 'TESTUSER',
                     'type' => 'first-come',
                     'userid' => 'TESTUSER'
                   },
                   {
                     'module' => 'Module::User::Foo',
                     'owner' => 'TESTUSER',
                     'type' => 'first-come',
                     'userid' => 'TESTUSER'
                   },
                   {
                     'module' => 'Module::User::Foo::Baz',
                     'owner' => 'TESTUSER',
                     'type' => 'first-come',
                     'userid' => 'TESTUSER'
                   },
                   {
                     'module' => 'Module::Comaint',
                     'owner' => 'TESTUSER2',
                     'type' => 'co-maint',
                     'userid' => 'TESTUSER'
                   },
                   {
                     'module' => 'Module::Comaint::Foo',
                     'owner' => 'TESTUSER2',
                     'type' => 'co-maint',
                     'userid' => 'TESTUSER'
                   },
                ] );
            }
        }
    }
};

subtest 'search by module (exact)' => sub {
    for my $method (qw/get_ok post_ok/) {
        for my $test (Test::PAUSE::Web->tests_for('user')) {
            my ($path, $user) = @$test;

            my $t = Test::PAUSE::Web->new(user => $user);

            my %form = (
                %$default,
                pause99_peek_perms_query => 'Module::User::Foo',
                pause99_peek_perms_by => 'me',
            );
            $t->$method("$path?ACTION=peek_perms", \%form);
            my @modules = map {$_->all_text} $t->dom->find('td.module')->each;
            my @types   = map {$_->all_text} $t->dom->find('td.type')->each;
            cmp_set(\@modules, [qw/
                Module::User::Foo
            /]) or note explain \@modules;
            ok grep(/co-maint/, @types), 'Has co-maint';
            # note $t->content;

            $t->$method("$path?ACTION=peek_perms&OF=YAML", \%form);
            my $list = YAML::Syck::Load( $t->content );
            eq_or_diff( $list => [
               {
                 'module' => 'Module::User::Foo',
                 'owner' => 'TESTUSER',
                 'type' => 'first-come',
                 'userid' => 'TESTUSER'
               },
               {
                 'module' => 'Module::User::Foo',
                 'owner' => 'TESTUSER',
                 'type' => 'co-maint',
                 'userid' => 'TESTADMIN'
               },
            ]);
        }
    }
};

subtest 'search by module (sql-like)' => sub {
    for my $method (qw/get_ok post_ok/) {
        for my $test (Test::PAUSE::Web->tests_for('user')) {
            my ($path, $user) = @$test;

            my $t = Test::PAUSE::Web->new(user => $user);

            my %form = (
                %$default,
                pause99_peek_perms_query => 'Module::User::%',
                pause99_peek_perms_by => 'ml',
            );
            $t->$method("$path?ACTION=peek_perms", \%form);
            my @modules = map {$_->all_text} $t->dom->find('td.module')->each;
            my @types   = map {$_->all_text} $t->dom->find('td.type')->each;
            cmp_set(\@modules, [qw/
                Module::User::Bar
                Module::User::Foo
                Module::User::Foo::Baz
            /]) or note explain \@modules;
            ok grep(/co-maint/, @types), 'Has co-maint';
            # note $t->content;

            $t->$method("$path?ACTION=peek_perms&OF=YAML", \%form);
            my $list = YAML::Syck::Load( $t->content );
            eq_or_diff( $list => [
               {
                 'module' => 'Module::User::Bar',
                 'owner' => 'TESTUSER',
                 'type' => 'first-come',
                 'userid' => 'TESTUSER'
               },
               {
                 'module' => 'Module::User::Foo',
                 'owner' => 'TESTUSER',
                 'type' => 'first-come',
                 'userid' => 'TESTUSER'
               },
               {
                 'module' => 'Module::User::Foo::Baz',
                 'owner' => 'TESTUSER',
                 'type' => 'first-come',
                 'userid' => 'TESTUSER'
               },
               {
                 'module' => 'Module::User::Bar',
                 'owner' => 'TESTUSER',
                 'type' => 'co-maint',
                 'userid' => 'TESTUSER2'
               },
               {
                 'module' => 'Module::User::Foo',
                 'owner' => 'TESTUSER',
                 'type' => 'co-maint',
                 'userid' => 'TESTADMIN'
               },
            ]);
        }
    }
};

done_testing;
