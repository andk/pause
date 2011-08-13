use strict;
use warnings;

use lib 't/lib';

use File::Spec;
use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

my $tmpdir = PAUSE::TestPAUSE->new({
  author_root => 'corpus/authors',
})->test;

ok(
  -e File::Spec->catfile($tmpdir, qw(cpan modules 02packages.details.txt.gz)),
  "our indexer indexed",
);

done_testing;
