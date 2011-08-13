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

my @want = (
  { package => 'Bug::Gold',      version => '9.001' },
  { package => 'Hall::MtKing',   version => '0.01'  },
  { package => 'XForm::Rollout', version => '1.00'  },
  { package => 'Y',              version => 2       },
);

subtest "tests with the data in the modules db" => sub {
  my $pkg_rows = $result->connect_mod_db->selectall_arrayref(
    'SELECT * FROM packages ORDER BY package, version',
    { Slice => {} },
  );

  cmp_deeply(
    $pkg_rows,
    [ map {; superhashof($_) } @want ],
    "we db-inserted exactly the dists we expected to",
  );
};

subtest "tests with the parsed 02packages data" => sub {
  my $p = $result->packages_data;

  my @packages = sort { $a->package cmp $b->package } $p->packages;

  cmp_deeply(
    \@packages,
    [ map {; methods(%$_) } @want ],
    "we built exactly the 02packages we expected",
  );
};

done_testing;
