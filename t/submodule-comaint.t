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

# Contains Jenkins-Hack-0.14 by OOOPPP which includes:
#
#   Jenkins::Hack
#   Jenkins::Hack2
#   Jenkins::Hack::Utils
#
my $corpus = 'corpus/mld/submodule-comaint/authors';

# However, Jenkins::Hack2 belongs to ATRION...
my @existing_permissions = map {
    "INSERT INTO $_ (package, userid) VALUES ('Jenkins::Hack2','ATRION')"
} qw/primeur perms/;

# ... and therefore, we should only index Jenkins::Hack and
# Jenkins::Hack::Utils
my $expected_package_list = [
    { package => 'Jenkins::Hack',        version => '0.14' },
    { package => 'Jenkins::Hack::Utils', version => '0.14' },
];

# Instantiate a new TestPAUSE
my $pause = PAUSE::TestPAUSE->init_new;

# Create the modules database, and add the existing permissions
my $dbh;
{
    my $db_file = File::Spec->catfile( $pause->db_root, 'mod.sqlite' );
    $dbh = DBI->connect(
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
      { subject => 'Failed: PAUSE indexer report OOOPPP/Jenkins-Hack-0.14.tar.gz' },
      { subject => 'Upload Permission or Version mismatch' },
  ],
);

# now lets add OOP as comaint on that and check we can upload it okay.
$dbh->do("INSERT INTO perms (package, userid) VALUES (?,?)", {},
        'Jenkins::Hack2','OOOPPP')
    or die "couldn't insert!";
$corpus = 'corpus/mld/submodule-comaint2/authors';
note("Indexing the corpus at [$corpus] now OOOPPP has comaint");
$pause->import_author_root( $corpus );
$result = $pause->test_reindex;
$result->email_ok(
  [
      { subject => 'PAUSE indexer report OOOPPP/Jenkins-Hack-0.15.tar.gz' },
  ],
);
$result->perm_list_ok(
  {
    'Jenkins::Hack'        => { f => 'OOOPPP' },
    'Jenkins::Hack2'       => { f => 'ATRION', c => [qw/OOOPPP/] },
    'Jenkins::Hack::Utils' => { f => 'OOOPPP' },
  }
);

done_testing;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
