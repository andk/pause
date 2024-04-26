use strict;
use warnings;

use 5.10.1;
use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE

use File::Spec;
use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

subtest "typical distribution that has both package and class with the same name in a file" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->upload_author_fake(RWP => 'App-APA-0.230470.tar.gz', {
    packages => [],  # do not allow faker to provide a default package
    append => [
      {
        file => "lib/App/APA.pm",
        content => <<'EOT',
use v5.37.9;
use experimental qw( class try builtin );
use builtin qw( true false trim );

package App::APA;

class App::APA;
EOT
      }
    ],
  });

  my $result = $pause->test_reindex;

  $result->package_list_ok([
    { package => 'App::APA', version => 'undef'  },
  ]);

  $result->perm_list_ok({
    'App::APA' => { f => 'RWP' },
  });
};

my @class_test_cases = (
    ['experimental class',     q{use experimental qw(class builtin);}],
    ['experimental all',       q{use experimental 'all';}],
    ['feature class',          q{use feature qw(class builtin);}],
    ['feature all',            q{use feature 'all';}],
    ['Feature::Compat::Class', q{use Feature::Compat::Class;}],
);

for my $test (@class_test_cases) {
  subtest "now we don't need a redundant package declaration if $test->[0] is used" => sub {
    my $pause = PAUSE::TestPAUSE->init_new;
    $pause->upload_author_fake(SOMEONE => 'Test-Class-1.00.tar.gz', {
      packages => [],  # do not allow faker to provide a default package
      append => [
        {
          file => "lib/Test/Class.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
class Test::Class;
EOT
        },
        {
          file => "lib/Test/ClassBlock.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
class Test::ClassBlock {
}
EOT
        },
        {
          file => "lib/Test/ClassVersion.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
class Test::ClassVersion 0.01;
EOT
        },
        {
          file => "lib/Test/ClassOurVersion.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
class Test::ClassOurVersion;
our \$VERSION = '0.02';
EOT
        },
        {
          file => "lib/Test/ClassVersionBlock.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
class Test::ClassVersionBlock 0.03 {
}
EOT
        },
        {
          file => "lib/Test/ClassBlockOurVersion.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
class Test::ClassBlockOurVersion {
  our \$VERSION = '0.04';
}
EOT
        },
      ],
    });

    my $result = $pause->test_reindex;

    $result->package_list_ok([
      { package => 'Test::Class',                version => 'undef'  },
      { package => 'Test::ClassBlock',           version => 'undef'  },
      { package => 'Test::ClassBlockOurVersion', version => '0.04'  },
      { package => 'Test::ClassOurVersion',      version => '0.02'  },
      { package => 'Test::ClassVersion',         version => '0.01'  },
      { package => 'Test::ClassVersionBlock',    version => '0.03'  },
    ]);

    $result->perm_list_ok({
      'Test::Class'                => { f => 'SOMEONE' },
      'Test::ClassBlock'           => { f => 'SOMEONE' },
      'Test::ClassVersion'         => { f => 'SOMEONE' },
      'Test::ClassOurVersion'      => { f => 'SOMEONE' },
      'Test::ClassVersionBlock'    => { f => 'SOMEONE' },
      'Test::ClassBlockOurVersion' => { f => 'SOMEONE' },
    });
  };
}

my @class_and_role_test_cases = (
    ['Object::Pad', q{use Object::Pad;}],
);

for my $test (@class_and_role_test_cases) {
  subtest "now we don't need a redundant package declaration if $test->[0] is used" => sub {
    my $pause = PAUSE::TestPAUSE->init_new;
    $pause->upload_author_fake(SOMEONE => 'Test-Class-1.00.tar.gz', {
      packages => [],  # do not allow faker to provide a default package
      append => [
        {
          file => "lib/Test/Class.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
class Test::Class;
EOT
        },
        {
          file => "lib/Test/ClassBlock.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
class Test::ClassBlock {
}
EOT
        },
        {
          file => "lib/Test/ClassVersion.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
class Test::ClassVersion 0.01;
EOT
        },
        {
          file => "lib/Test/ClassOurVersion.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
class Test::ClassOurVersion;
our \$VERSION = '0.02';
EOT
        },
        {
          file => "lib/Test/ClassVersionBlock.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
class Test::ClassVersionBlock 0.03 {
}
EOT
        },
        {
          file => "lib/Test/ClassBlockOurVersion.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
class Test::ClassBlockOurVersion {
  our \$VERSION = '0.04';
}
EOT
        },
        {
          file => "lib/Test/Role.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
class Test::Role;
EOT
        },
        {
          file => "lib/Test/RoleBlock.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
role Test::RoleBlock {
}
EOT
        },
        {
          file => "lib/Test/RoleVersion.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
role Test::RoleVersion 0.01;
EOT
        },
        {
          file => "lib/Test/RoleOurVersion.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
role Test::RoleOurVersion;
our \$VERSION = '0.02';
EOT
        },
        {
          file => "lib/Test/RoleVersionBlock.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
role Test::RoleVersionBlock 0.03 {
}
EOT
        },
        {
          file => "lib/Test/RoleBlockOurVersion.pm",
          content => <<"EOT",
use v5.37.9;
$test->[1]
use builtin qw( true false trim );
 
role Test::RoleBlockOurVersion {
  our \$VERSION = '0.04';
}
EOT
        },
      ],
    });

    my $result = $pause->test_reindex;

    $result->package_list_ok([
      { package => 'Test::Class',                version => 'undef'  },
      { package => 'Test::ClassBlock',           version => 'undef'  },
      { package => 'Test::ClassBlockOurVersion', version => '0.04'  },
      { package => 'Test::ClassOurVersion',      version => '0.02'  },
      { package => 'Test::ClassVersion',         version => '0.01'  },
      { package => 'Test::ClassVersionBlock',    version => '0.03'  },
      { package => 'Test::Role',                 version => 'undef'  },
      { package => 'Test::RoleBlock',            version => 'undef'  },
      { package => 'Test::RoleBlockOurVersion',  version => '0.04'  },
      { package => 'Test::RoleOurVersion',       version => '0.02'  },
      { package => 'Test::RoleVersion',          version => '0.01'  },
      { package => 'Test::RoleVersionBlock',     version => '0.03'  },
    ]);

    $result->perm_list_ok({
      'Test::Class'                => { f => 'SOMEONE' },
      'Test::ClassBlock'           => { f => 'SOMEONE' },
      'Test::ClassVersion'         => { f => 'SOMEONE' },
      'Test::ClassOurVersion'      => { f => 'SOMEONE' },
      'Test::ClassVersionBlock'    => { f => 'SOMEONE' },
      'Test::ClassBlockOurVersion' => { f => 'SOMEONE' },
      'Test::Role'                 => { f => 'SOMEONE' },
      'Test::RoleBlock'            => { f => 'SOMEONE' },
      'Test::RoleVersion'          => { f => 'SOMEONE' },
      'Test::RoleOurVersion'       => { f => 'SOMEONE' },
      'Test::RoleVersionBlock'     => { f => 'SOMEONE' },
      'Test::RoleBlockOurVersion'  => { f => 'SOMEONE' },
    });
  };
}

done_testing;

