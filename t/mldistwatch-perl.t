use strict;
use warnings;

use 5.10.1;
use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE

use File::Spec;
use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

subtest "perl-\\d should not get indexed (not really perl)" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;

  $pause->upload_author_fake(PLUGH => 'Soft-Ware-2');

  $pause->upload_author_fake(PLUGH => {
    name      => 'perl',
    version   => 6,
    packages  => [ 'perl::rocks' ],
  });

  my $result = $pause->test_reindex;

  $result->package_list_ok(
    [
      { package => 'Soft::Ware',      version => '2' },
    ],
  );

  # TODO: send a report saying 'no perl-X allowed'

  $result->logged_event_like(
    qr{dist is an unofficial perl-like release},
    "perl-6.tar.gz is not a really perl-like file",
  );
};

subtest "should index single-life dev vers. modules in perl dist" => sub {
  plan skip_all => "this test only run when perl-5.20.2.tar.gz found"
    unless -e 'perl-5.20.2.tar.gz';

  my $pause = PAUSE::TestPAUSE->init_new;

  my $initial_result = $pause->test_reindex;

  my $dbh = $initial_result->connect_authen_db;
  die "couldn't make OPRIME a pumpking"
    unless $dbh->do("INSERT INTO grouptable (user, ugroup) VALUES ('OPRIME', 'pumpking')");

  $pause->upload_author_file('OPRIME', 'perl-5.20.2.tar.gz');

  my $result = $pause->test_reindex;

  my $packages = $result->packages_data;
  ok($packages->package("POSIX"), "we index POSIX in a dev version");
};

subtest "reject perl by unauthorized user" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;

  my $initial_result = $pause->test_reindex;
  my $dbh = $initial_result->connect_authen_db;

  $pause->upload_author_fake(OPRIME => {
    name      => 'perl',
    version   => '5.56.55',
    packages  => [ 'Perl::Core' ],
    packages  => [
      'Perl::Core' => { version => '1.002' },
    ],
  });

  my $result = $pause->test_reindex;

  $result->assert_index_not_updated;

  $result->logged_event_like(
    qr{\Qperl dist O/OP/OPRIME/perl-5.56.55.tar.gz from untrusted user OPRIME},
    "rejected because user it not trusted to upload perl",
  );
};

subtest "indexing a new perl and then another one" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;

  my $initial_result = $pause->test_reindex;
  my $dbh = $initial_result->connect_authen_db;

  die "couldn't make OPRIME a pumpking"
    unless $dbh->do("INSERT INTO grouptable (user, ugroup) VALUES ('OPRIME', 'pumpking')");

  subtest "first version of perl" => sub {
    $pause->upload_author_fake(OPRIME => {
      name      => 'perl',
      version   => '5.56.55',
      packages  => [
        'Perl::Core'    => { version => '1.002' },
        'Little::Buddy' => { version => '2.003' },
      ],
    });

    my $result = $pause->test_reindex;

    $result->package_list_ok(
      [
        { package => 'Little::Buddy', version => '2.003' },
        { package => 'Perl::Core',    version => '1.002' },
      ],
    );
  };

  subtest "re-upload that same version again" => sub {
    $pause->upload_author_fake(OPRIME => {
      name      => 'perl',
      version   => '5.56.55',
      packages  => [
        'Perl::Core'    => { version => '1.002' },
        'Little::Buddy' => { version => '2.003' },
      ],
    });

    my $result = $pause->test_reindex;

    $result->package_list_ok(
      [
        { package => 'Little::Buddy', version => '2.003' },
        { package => 'Perl::Core',    version => '1.002' },
      ],
    );
  };

  subtest "actual next version of perl" => sub {
    $pause->upload_author_fake(OPRIME => {
      name      => 'perl',
      version   => '5.56.56',
      packages  => [
        'Little::Buddy' => { version => '2.345' },
        'Newly::Added'  => { version => '3.000' },
        'Perl::Core'    => { version => '1.002' },
      ],
    });

    my $result = $pause->test_reindex;

    $result->package_list_ok(
      [
        { package => 'Little::Buddy', version => '2.345' },
        { package => 'Newly::Added',  version => '3.000' },
        { package => 'Perl::Core',    version => '1.002' },
      ],
    );
  };
};

subtest "indexing a new perl, but file is not a proper tar.gz" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;

  my $initial_result = $pause->test_reindex;
  my $dbh = $initial_result->connect_authen_db;

  die "couldn't make OPRIME a pumpking"
    unless $dbh->do("INSERT INTO grouptable (user, ugroup) VALUES ('OPRIME', 'pumpking')");

  $pause->upload_author_garbage(OPRIME => "perl-5.56.55.tar.gz");

  my $result = $pause->test_reindex;

  $result->assert_index_not_updated;

  $result->logged_event_like(
    qr{\Qcould not untar O/OP/OPRIME/perl-5.56.55.tar.gz},
    "you can't index what you can't extract",
  );
};

subtest "perl uploads do not unseat dual-life modules" => sub {
  # When a perl dist upload includes a new version of something currently
  # indexed in a non-perl dist, we do not replace it in the index.  This test
  # is for that rule.
  my $pause = PAUSE::TestPAUSE->init_new;

  my $initial_result = $pause->test_reindex;
  my $dbh = $initial_result->connect_authen_db;

  die "couldn't make OPRIME a pumpking"
    unless $dbh->do("INSERT INTO grouptable (user, ugroup) VALUES ('OPRIME', 'pumpking')");

  subtest "upload the standalone version of a dual-life dist" => sub {
    $pause->upload_author_fake(OPRIME => "Little-Buddy-1.000.tar.gz");
    my $result = $pause->test_reindex;

    $result->package_list_ok(
      [
        { package => 'Little::Buddy', version => '1.000' },
      ],
    );
  };

  subtest "upload the in-core version of a dual-life dist" => sub {
    $pause->upload_author_fake(OPRIME => {
      name      => 'perl',
      version   => '5.56.55',
      packages  => [
        'Perl::Core'    => { version => '1.002' },
        'Little::Buddy' => { version => '2.003' },
      ],
    });

    my $result = $pause->test_reindex;

    $result->package_list_ok(
      [
        { package => 'Little::Buddy', version => '1.000' },
        { package => 'Perl::Core',    version => '1.002' },
      ],
    );
  };
};

subtest "non-perl can replace perl versions" => sub {
  # The "separate then in-core" rule which says that the core won't shadow a
  # separate upload only goes in one direction.  If a library is first found in
  # core, and then later uploaded outside, the newly uploaded package may
  # become indexed in that new dist.
  my $pause = PAUSE::TestPAUSE->init_new;

  my $initial_result = $pause->test_reindex;
  my $dbh = $initial_result->connect_authen_db;

  die "couldn't make OPRIME a pumpking"
    unless $dbh->do("INSERT INTO grouptable (user, ugroup) VALUES ('OPRIME', 'pumpking')");

  my $perl_dist  = 'O/OP/OPRIME/perl-5.56.55.tar.gz';
  my $other_dist = 'O/OP/OPRIME/Little-Buddy-3.000.tar.gz';

  subtest "upload the in-core version of a dual-life dist" => sub {
    $pause->upload_author_fake(OPRIME => {
      name      => 'perl',
      version   => '5.56.55',
      packages  => [
        'Little::Buddy' => { version => '2.000' },
        'Perl::Core'    => { version => '1.002' },
      ],
    });

    my $result = $pause->test_reindex;

    $result->package_list_ok(
      [
        { package => 'Little::Buddy', version => '2.000' },
        { package => 'Perl::Core',    version => '1.002' },
      ],
    );
  };

  subtest "upload the standalone version of a dual-life dist" => sub {
    $pause->upload_author_fake(OPRIME => "Little-Buddy-3.000.tar.gz");
    my $result = $pause->test_reindex;

    $result->package_list_ok(
      [
        { package => 'Little::Buddy', version => '3.000' },
        { package => 'Perl::Core',    version => '1.002' },
      ],
    );
  };
};

done_testing;
