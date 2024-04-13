#
# losing-first-come.t
#
# This test was written to demonstrate a bug that is causing authors
# to lose a first-come permission, in a particular setup and release scenario.
#
# Setup:
#   user FORD has first-come on package Guide (but an entry in `primeur` only)
#   user ARTHUR has co-maint on package Guide (an entry in `perms`)
#
# First-come does a release, then co-maint does a release
#   0. Setup as above
#   1. FORD does a release, and afterwards both permissions are still present
#   2. ARTHUR then does a release, and the perms are still present as well
#
# Co-maint does the first release
#   3. Setup as above
#   4. ARTHUR does a release. The bug is that the entry in `primeur` gets lost
#   
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

add_to_primeur($pause, "FORD" => "Guide");
$pause->add_comaint("ARTHUR" => "Guide");

# First the person with first-come does a release

$pause->upload_author_fake(
    FORD => {
        name => "Guide",
        version => 0.001,
        packages => [
            Guide => { in_file => "lib/Guide.pm" }
        ]
    }
);

my $result = $pause->test_reindex;

$result->package_list_ok([
    { package => 'Guide', version => '0.001' },
]);

$result->perm_list_ok(
    {
        Guide => { f => "FORD", c => ["ARTHUR"] }
    }
);

# Now the co-maint does the next release.
$pause->upload_author_fake(
    ARTHUR => {
        name => "Guide",
        version => 0.002,
        packages => [
            Guide => { in_file => "lib/Guide.pm" }
        ]
    }
);

$result = $pause->test_reindex;

$result->package_list_ok([
    { package => 'Guide', version => '0.002' },
]);

$result->perm_list_ok(
    {
        Guide => { f => "FORD", c => ["ARTHUR"] }
    }
);


$pause = PAUSE::TestPAUSE->init_new;

add_to_primeur($pause, "FORD" => "Guide");
$pause->add_comaint("ARTHUR" => "Guide");

# This time the co-maint does the first release
$pause->upload_author_fake(
    ARTHUR => {
        name => "Guide",
        version => 0.001,
        packages => [
            Guide => { in_file => "lib/Guide.pm" }
        ]
    }
);

$result = $pause->test_reindex;

$result->package_list_ok([
    { package => 'Guide', version => '0.001' },
]);

$result->perm_list_ok(
    {
        Guide => { f => "FORD", c => ["ARTHUR"] }
    }
);

done_testing();

# PAUSE::TestPAUSE has add_first_come() and add_comaint() methods.
# This function is like one of those methods, but an odd one.
# A first-come permission is really indicated by the author having
# an entry in both the primeur and perms tables.
# But for this test I want to check what happens when someone has
# an entry for a package in primeur only.
sub add_to_primeur
{
    my ($pause, $author, $package) = @_;

    my $db_file = File::Spec->catfile( $pause->db_root, 'mod.sqlite' );
    my $db      = DBI->connect( "dbi:SQLite:dbname=$db_file", undef, undef)
                  or die "can't connect to db at $db_file: $DBI::errstr";

    $db->do("INSERT INTO primeur (userid, package, lc_package) VALUES (?, ?, ?);",
            undef, $author, $package, lc $package)
        or die "couldn't add to primeur for $author/$package: $DBI::errstr\n";

}

