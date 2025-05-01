use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;
use YAML::Syck;
use Test::Deep;
use Test::Differences;

my $default = {
    pause99_peek_dist_perms_query => "TESTUSER",
    pause99_peek_dist_perms_by => "a",
    pause99_peek_dist_perms_sub => 1,
};

Test::PAUSE::Web->setup;
Test::PAUSE::Web->reset_module_fixture;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new(user => $user);
        $t->get_ok("$path?ACTION=peek_dist_perms");
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
                pause99_peek_dist_perms_query => $user,
            );
            $t->$method("$path?ACTION=peek_dist_perms", \%form);
            my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
            if ($user eq 'TESTADMIN') {
                cmp_bag(\@dists, [qw/
                    Module-Admin
                    Module-Comaint
                    Module-User
                /]) or note explain \@dists;
                ok grep(/^Module-Comaint/, @dists), 'Module-Comaint is also listed';
            }
            if ($user eq 'TESTUSER') {
                cmp_bag(\@dists, [qw/
                    Module-Comaint
                    Module-User
                    Module-User-Foo-Baz
                /]) or note explain \@dists;
            }
            # note $t->content;

            $t->$method("$path?ACTION=peek_dist_perms&OF=YAML", \%form);
            my $list = YAML::Syck::Load( $t->content );
            if ($user eq 'TESTADMIN') {
                eq_or_diff( $list => [
                   {
                     'dist' => 'Module-Admin',
                     'owner' => 'TESTADMIN',
                     'comaint' => 'TESTUSER2',
                   },
                   {
                     'dist' => 'Module-Comaint',
                     'owner' => 'TESTUSER2',
                     'comaint' => 'TESTADMIN',
                   },
                   {
                     'dist' => 'Module-User',
                     'owner' => 'TESTUSER',
                     'comaint' => 'TESTADMIN',
                   },
                ] );
            }
            if ($user eq 'TESTUSER') {
                eq_or_diff( $list => [
                   {
                     'dist' => 'Module-Comaint',
                     'owner' => 'TESTUSER2',
                     'comaint' => 'TESTUSER',
                   },
                   {
                     'dist' => 'Module-User',
                     'owner' => 'TESTUSER',
                     'comaint' => 'TESTADMIN,TESTUSER2',
                   },
                   {
                     'dist' => 'Module-User-Foo-Baz',
                     'owner' => 'TESTUSER',
                     'comaint' => undef,
                   },
                ] );
            }
        }
    }
};

subtest 'search by dist (exact)' => sub {
    for my $method (qw/get_ok post_ok/) {
        for my $test (Test::PAUSE::Web->tests_for('user')) {
            my ($path, $user) = @$test;

            my $t = Test::PAUSE::Web->new(user => $user);

            my %form = (
                %$default,
                pause99_peek_dist_perms_query => 'Module-User',
                pause99_peek_dist_perms_by => 'de',
            );
            $t->$method("$path?ACTION=peek_dist_perms", \%form);
            my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
            cmp_set(\@dists, [qw/
                Module-User
            /]) or note explain \@dists;
            # note $t->content;

            $t->$method("$path?ACTION=peek_dist_perms&OF=YAML", \%form);
            my $list = YAML::Syck::Load( $t->content );
            eq_or_diff( $list => [
               {
                 'dist' => 'Module-User',
                 'owner' => 'TESTUSER',
                 'comaint' => 'TESTADMIN,TESTUSER2',
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
                pause99_peek_dist_perms_query => 'Module-User%',
                pause99_peek_dist_perms_by => 'dl',
            );
            $t->$method("$path?ACTION=peek_dist_perms", \%form);
            my @dists = map {$_->all_text} $t->dom->find('td.dist')->each;
            cmp_set(\@dists, [qw/
                Module-User
                Module-User-Foo-Baz
            /]) or note explain \@dists;
            # note $t->content;

            $t->$method("$path?ACTION=peek_dist_perms&OF=YAML", \%form);
            my $list = YAML::Syck::Load( $t->content );
            eq_or_diff( $list => [
               {
                 'dist' => 'Module-User',
                 'owner' => 'TESTUSER',
                 'comaint' => 'TESTADMIN,TESTUSER2',
               },
               {
                 'dist' => 'Module-User-Foo-Baz',
                 'owner' => 'TESTUSER',
                 'comaint' => undef,
               },
            ]);
        }
    }
};

done_testing;
