use strict;
use warnings;

use v5.36.0;
use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE

use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

# Module::Faker doesn't put "provides" into META unless asked, so these dists
# are indexed by scanning their files, which is where package and namespace
# no_index rules get applied.
sub no_index_ok ($desc, $no_index, $want_packages) {
  subtest $desc => sub {
    my $pause = PAUSE::TestPAUSE->init_new;

    $pause->upload_author_fake(PERSON => {
      name     => 'Foo-Bar',
      version  => '1.000',
      no_index => $no_index,
      packages => [
        map {; $_ => { version => '1.000' } }
          qw( Foo::Bar Foo::Bar::Util Foo::Bar::Internal Foo::Bar::Internal::X )
      ],
    });

    my $result = $pause->test_reindex;

    $result->package_list_ok([
      map {; { package => $_, version => '1.000' } } @$want_packages
    ]);
  };
}

no_index_ok(
  "no no_index at all",
  undef,
  [ qw( Foo::Bar Foo::Bar::Internal Foo::Bar::Internal::X Foo::Bar::Util ) ],
);

no_index_ok(
  "only directory rules",
  { directory => [ qw( t inc ) ] },
  [ qw( Foo::Bar Foo::Bar::Internal Foo::Bar::Internal::X Foo::Bar::Util ) ],
);

no_index_ok(
  "package rule",
  { package => [ 'Foo::Bar::Util' ] },
  [ qw( Foo::Bar Foo::Bar::Internal Foo::Bar::Internal::X ) ],
);

no_index_ok(
  "package rule given as a string, not a list",
  { package => 'Foo::Bar::Util' },
  [ qw( Foo::Bar Foo::Bar::Internal Foo::Bar::Internal::X ) ],
);

no_index_ok(
  "namespace rule excludes packages under it, not the namespace itself",
  { namespace => [ 'Foo::Bar::Internal' ] },
  [ qw( Foo::Bar Foo::Bar::Internal Foo::Bar::Util ) ],
);

no_index_ok(
  "namespace rule with trailing colons",
  { namespace => [ 'Foo::Bar::Internal::' ] },
  [ qw( Foo::Bar Foo::Bar::Internal Foo::Bar::Util ) ],
);

no_index_ok(
  "package and namespace rules together",
  {
    directory => [ qw( t inc ) ],
    package   => [ 'Foo::Bar::Util' ],
    namespace => [ 'Foo::Bar::Internal' ],
  },
  [ qw( Foo::Bar Foo::Bar::Internal ) ],
);

done_testing;
