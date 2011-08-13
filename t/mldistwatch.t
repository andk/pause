use strict;
use warnings;

use lib 't/lib';

use File::Spec;
use PAUSE;
use PAUSE::TestPAUSE;

use Test::Deep;
use Test::More;

my $result = PAUSE::TestPAUSE->new({
  author_root => 'corpus/authors',
})->test;

ok(
  -e $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
  "our indexer indexed",
);

my $pkg_rows = $result->connect_mod_db->selectall_arrayref(
  'SELECT * FROM packages ORDER BY package, version',
  { Slice => {} },
);

my @want = (
  { package => 'Bug::Gold',      version => '9.001' },
  { package => 'Hall::MtKing',   version => '0.01'  },
  { package => 'XForm::Rollout', version => '1.00'  },
  { package => 'Y',              version => 2       },
);

cmp_deeply(
  $pkg_rows,
  [ map {; superhashof($_) } @want ],
  "we indexed exactly the dists we expected to",
);

done_testing;
