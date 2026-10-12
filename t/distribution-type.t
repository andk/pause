use strict;
use warnings;

use v5.36.0;
use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE

use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

# META spec 1.x let a dist declare distribution_type "script" (a program to
# run) or "module".  PAUSE doesn't index dists that say they're scripts.
sub distribution_type_ok ($type, $want_packages, $want_subjects) {
  subtest "distribution_type: $type" => sub {
    my $pause = PAUSE::TestPAUSE->init_new;

    $pause->upload_author_fake(PERSON => {
      name        => 'Foo-Bar',
      version     => '1.000',
      meta_munger => sub ($meta, @) {
        $meta->{distribution_type} = $type;
        return $meta;
      },
    });

    my $result = $pause->test_reindex;

    $result->package_list_ok([
      map {; { package => $_, version => '1.000' } } @$want_packages
    ]);

    $result->email_ok([ map {; { subject => $_ } } @$want_subjects ]);
  };
}

distribution_type_ok(
  module => [ 'Foo::Bar' ],
  [ 'PAUSE indexer report PERSON/Foo-Bar-1.000.tar.gz' ],
);

distribution_type_ok(
  script => [],
  [ 'Failed: PAUSE indexer report PERSON/Foo-Bar-1.000.tar.gz' ],
);

done_testing;
