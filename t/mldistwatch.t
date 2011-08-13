use strict;
use warnings;

use lib 't/lib';

use File::Spec;
use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

my $result = PAUSE::TestPAUSE->new({
  author_root => 'corpus/authors',
})->test;

ok(
  -e $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
  "our indexer indexed",
);

done_testing;
