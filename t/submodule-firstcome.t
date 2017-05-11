# The header has been lifted from mldist-misc.t untouched
use strict;
use warnings;

use 5.10.1;
use lib 't/lib';
use lib 't/lib/privatelib';    # Stub PrivatePAUSE

use Email::Sender::Transport::Test;
$ENV{EMAIL_SENDER_TRANSPORT} = 'Test';

use File::Spec;
use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

# Contains Acme-Playpen-2.00 by NEILB which includes:
# Acme::Playpen
# Acme::Playpen::NonIndexedFile
# Acme::Playpen::NonIndexedPackage
# Acme::Playpen::Utilities
# Acme::STUDY::PERL
my $corpus = 'corpus/mld/submodule-firstcome/authors';

# However, Acme::Study::Perl belongs to ANDK.
my @existing_permissions = map {
    "INSERT INTO $_ (package, userid) VALUES ('Acme::Study::Perl','ANDK')"
} qw/primeur perms/;

# ... and therefore, we should only index Acme::Playpen::*
my $expected_package_list = [
    { package => 'Acme::Playpen',            version => '0.20' },
    { package => 'Acme::Playpen::Utilities', version => 'undef' },
    { package => 'Acme::Playpen::_common',   version => 'undef' },
    { package => 'Acme::odometer',           version => '0.20' },
    ### { package => 'Acme::STUDY::PERL',        version => '2.00' }, ### WRONG
];

# Instantiate a new TestPAUSE
my $pause = PAUSE::TestPAUSE->init_new;

# Create the modules database, and add the existing permissions
{
    my $db_file = File::Spec->catfile( $pause->db_root, 'mod.sqlite' );
    my $dbh = DBI->connect(
        'dbi:SQLite:dbname='
            . $db_file,
        undef,
        undef,
    ) or die "can't connect to db at $db_file: $DBI::errstr";

    for my $perm (@existing_permissions) {
        $dbh->do($perm) or die "Couldn't add package permissions [$perm]";
    }

}

note("Indexing the corpus at [$corpus]");
$pause->import_author_root( $corpus );
my $result = $pause->test_reindex;

# Check the results using Rik's convenience method
$result->package_list_ok( $expected_package_list );

$result->email_ok(
  [
      { subject => 'Failed: PAUSE indexer report NEILB/Acme-Playpen-2.00.tar.gz' },
      { subject => 'Upload Permission or Version mismatch' },
  ],
);

done_testing;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
