use strict;
use warnings;

use v5.36.0;
use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE

use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

# The indexer reads files with "while (<FH>)", which assigns to $_.  If $_ is
# aliased to a read-only value when we get there, that dies with "Modification
# of a read-only value attempted", unless the indexer localizes $_ first.
sub _reindex_with_readonly_underscore ($pause) {
  my $result;

  for ("this string is read-only") {
    $result = eval { $pause->test_reindex };
  }

  fail("indexer run died: $@") unless $result;
  return $result;
}

sub p5_index_ok_with_readonly_underscore ($upload, $want_packages) {
  subtest "index $upload with read-only \$_" => sub {
    my $pause = PAUSE::TestPAUSE->init_new;
    $pause->upload_author_fake(PERSON => $upload);

    my $result = _reindex_with_readonly_underscore($pause) or return;

    $result->package_list_ok($want_packages);
  };
}

sub p6_index_ok_with_readonly_underscore ($author_root, $want_dists) {
  subtest "index $author_root with read-only \$_" => sub {
    my $pause = PAUSE::TestPAUSE->init_new;
    $pause->import_author_root($author_root);

    my $result = _reindex_with_readonly_underscore($pause) or return;

    $result->p6dists_ok($want_dists);
  };
}

p5_index_ok_with_readonly_underscore(
  'Foo-Bar-1.000.tar.gz',
  [ { package => 'Foo::Bar', version => '1.000' } ],
);

p6_index_ok_with_readonly_underscore(
  'corpus/mld/perl6/authors',
  [ { name => 'Inline', ver => '1.1' } ],
);

done_testing;
