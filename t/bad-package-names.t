use strict;
use warnings;

use v5.36.0;
use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE

use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

# We should reject dists with malformed package names.
sub bad_provides_name_ok ($bad_name) {
  subtest "provides includes malformed name '$bad_name'" => sub {
    my $pause = PAUSE::TestPAUSE->init_new;

    $pause->upload_author_fake(PERSON => {
      name     => 'Foo-Bar',
      version  => '1.000',
      packages => [ map {; $_ => { version => '1.000' } } qw(Foo::Bar Foo::Bar::Util) ],
      include_provides_in_meta => 1,
      meta_munger => sub ($meta, @) {
        $meta->{provides}{$bad_name} = {
          file    => 'lib/Foo/Bar.pm',
          version => '1.000',
        };
        return $meta;
      },
    });

    $pause->upload_author_fake(PERSON => 'Other-Dist-1.000.tar.gz');

    my $result = eval { $pause->test_reindex };

    unless ($result) {
      fail("indexer run died: $@");
      return;
    }

    $result->package_list_ok([
      map {; { package => $_, version => '1.000' } }
        qw(Other::Dist)
    ]);

    $result->email_ok([
      { subject => 'Failed: PAUSE indexer report PERSON/Foo-Bar-1.000.tar.gz' },
      { subject => 'PAUSE indexer report PERSON/Other-Dist-1.000.tar.gz' },
    ]);
  };
}

bad_provides_name_ok('Foo:Bar');
bad_provides_name_ok('Foo::Bar::');
bad_provides_name_ok('Foo-Bar');
bad_provides_name_ok('Foo:::Bar');
bad_provides_name_ok('::Foo');

done_testing;
