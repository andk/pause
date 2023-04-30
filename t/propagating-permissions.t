#
# propagating-permissions.t
#
# This tests that permissions on the lead package are
# propagated to everyone who has permissions on that
# package, regardless of who does the release
#
use strict;
use warnings;

use 5.10.1;
use lib 't/lib';
use lib 't/privatelib';    # Stub PrivatePAUSE

use DBI;
use File::Spec;
use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

# Set up permissions

my $pause = PAUSE::TestPAUSE->init_new;

# First the person with first-come does a release

$pause->upload_author_fake(
    BILBO => {
        name => "Hobbit",
        version => 0.001,
        packages => [
            Hobbit => { in_file => "lib/Hobbit.pm" }
        ]
    }
);

my $result = $pause->test_reindex;

$result->package_list_ok([
    { package => 'Hobbit', version => '0.001' },
]);

$result->perm_list_ok(
    {
        Hobbit => { f => "BILBO" }
    }
);

# BILBO gives co-maint to FRODO
$pause->add_comaint("FRODO" => "Hobbit");

$result = $pause->test_reindex;

$result->package_list_ok([
    { package => 'Hobbit', version => '0.001' },
]);

$result->perm_list_ok(
    {
        Hobbit => { f => "BILBO", c => ["FRODO"] }
    }
);

# Then BILBO does another release that adds a second package
# BILBO should get first-come on that, FRODO should get co-maint

$pause->upload_author_fake(
    BILBO => {
        name => "Hobbit",
        version => 0.002,
        packages => [
            Breakfast => { in_file => "lib/Breakfast.pm" },
            Hobbit    => { in_file => "lib/Hobbit.pm" },
        ]
    }
);

$result = $pause->test_reindex;

$result->package_list_ok([
    { package => 'Breakfast', version => '0.002' },
    { package => 'Hobbit', version => '0.002' },
]);

$result->perm_list_ok(
    {
        Breakfast => { f => "BILBO", c => ["FRODO"] },
        Hobbit    => { f => "BILBO", c => ["FRODO"] },
    }
);

# Now FRODO does a release, and he adds a package.
# He should co-maint on the new package, and BILBO
# should get the first come

$pause->upload_author_fake(
    FRODO => {
        name => "Hobbit",
        version => 0.003,
        packages => [
            Breakfast => { in_file => "lib/Breakfast.pm" },
            Hobbit    => { in_file => "lib/Hobbit.pm" },
            Sting     => { in_file => "lib/Sting.pm" },
        ]
    }
);

$result = $pause->test_reindex;

$result->package_list_ok([
    { package => 'Breakfast', version => '0.003' },
    { package => 'Hobbit',    version => '0.003' },
    { package => 'Sting',     version => '0.003' },
]);

$result->perm_list_ok(
    {
        Breakfast => { f => "BILBO", c => ["FRODO"] },
        Hobbit    => { f => "BILBO", c => ["FRODO"] },
        Sting     => { f => "BILBO", c => ["FRODO"] },
    }
);

done_testing();

