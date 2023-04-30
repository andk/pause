use strict;
use warnings;

use 5.10.1;
use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE

use File::Spec;
use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

subtest "first indexing" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/001/authors');

  my $result = $pause->test_reindex;

  $result->assert_index_updated;

  $result->package_list_ok(
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'Jenkins::Hack',  version => '0.11'  },
      { package => 'Mooooooose',     version => '0.01'  },
      { package => 'XForm::Rollout', version => '1.00'  },
      { package => 'Y',              version => 2       },
    ],
  );

  $result->perm_list_ok(
    {
      'Bug::Gold'       => { f => 'OPRIME' },
      'Hall::MtKing'    => { f => 'XYZZY'  },
      'Jenkins::Hack'   => { f => 'OOOPPP' },
      'Mooooooose'      => { f => 'AAARGH' },
      'XForm::Rollout'  => { f => 'OPRIME' },
      'Y',              => { f => 'XYZZY'  },
    }
  );

  $result->email_ok(
    [
      { subject => 'PAUSE indexer report AAARGH/Mooooooose-0.01.tar.gz' },
      { subject => 'PAUSE indexer report OOOPPP/Jenkins-Hack-0.11.tar.gz' },
      { subject => 'PAUSE indexer report OPRIME/Bug-Gold-9.001.tar.gz' },
      { subject => 'PAUSE indexer report OPRIME/XForm-Rollout-1.00.tar.gz' },
      { subject => 'PAUSE indexer report XYZZY/Hall-MtKing-0.01.tar.gz' },
      { subject => 'PAUSE indexer report XYZZY/Y-2.tar.gz' },
    ],
  );

  subtest "meagre git tests" => sub {
    ok(
      -e $result->tmpdir->file('git/.git/refs/heads/master')
        || -e $result->tmpdir->file('git/.git/refs/heads/main'),
      "we now have a master or main commit",
    );
  };
};

for my $uploader (qw(FCOME CMAINT)) {
  subtest "new module added by $uploader are copied to comaints" => sub {
    my $pause = PAUSE::TestPAUSE->init_new;

    $pause->upload_author_fake(FCOME => 'Elk-0.01');

    $pause->test_reindex->package_list_ok([
      { package => 'Elk',             version => '0.01'  },
    ]);

    $pause->add_comaint(CMAINT  => 'Elk');
    $pause->add_comaint(THIRD   => 'Elk');

    $pause->test_reindex->perm_list_ok({
      'Elk'             => { f => 'FCOME', c => [qw/CMAINT THIRD/] },
    });

    $pause->upload_author_fake($uploader => {
      name      => 'Elk',
      version   => 0.02,
      packages  => [ qw(Elk Elk::Role) ],
    });

    {
      my $result = $pause->test_reindex;

      $result->assert_index_updated;

      $result->package_list_ok(
        [
          { package => 'Elk',             version => '0.02'  },
          { package => 'Elk::Role',       version => '0.02'  },
        ],
      );

      $pause->test_reindex->perm_list_ok({
        'Elk'             => { f => 'FCOME', c => [qw/CMAINT THIRD/] },
        'Elk::Role'       => { f => 'FCOME', c => [qw/CMAINT THIRD/] },
      });

      $result->email_ok(
        [
          { subject => "PAUSE indexer report $uploader/Elk-0.02.tar.gz" },
        ],
      );
    }
  };
}

subtest "require permission on main module" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;

  $pause->upload_author_fake(UMAGNUS => 'XForm-Rollout-1.00');

  $pause->test_reindex->package_list_ok([
    { package => 'XForm::Rollout', version => '1.00' },
  ]);

  $pause->upload_author_fake(UMAGNUS => {
    name      => 'XFR',
    version   => '2.000',
    packages  => 'XForm::Rollout',
  });

  my $result = $pause->test_reindex;

  $result->package_list_ok([
      { package => 'XForm::Rollout', version => '1.00'  },
    ],
  );

  $result->email_ok(
    [
      { subject => 'Failed: PAUSE indexer report UMAGNUS/XFR-2.000.tar.gz' ,
        callbacks => [
          sub {
            like(
              $_[0]->{email}->as_string,
              qr/package\s+would\s+be\s+called\s+XFR/,
              "email looks right",
            );
          },
        ],
      },
      { subject => 'PAUSE upload indexing error' },
    ],
  );
};

subtest "don't allow upload on permissions case conflict" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;

  $pause->upload_author_fake(OPRIME => 'XForm-Rollout-1.00');

  $pause->test_reindex->package_list_ok([
    { package => 'XForm::Rollout', version => '1.00' },
  ]);

  $pause->upload_author_fake(XYZZY => 'xform-rollout-2.00');

  my $result = $pause->test_reindex;

  $result->package_list_ok([
    { package => 'XForm::Rollout', version => '1.00' },
  ]);

  $result->email_ok(
    [
      { subject => 'Failed: PAUSE indexer report XYZZY/xform-rollout-2.00.tar.gz' },
      { subject => 'PAUSE upload indexing error' },
    ],
  );
};

subtest "case mismatch, authorized for original" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;

  $pause->upload_author_fake(OPRIME => 'XForm-Rollout-1.00');

  $pause->test_reindex->package_list_ok(
    [
      { package => 'XForm::Rollout', version => '1.00'  },
    ],
  );

  $pause->upload_author_fake(OPRIME => 'xform-rollout-2.00');

  my $result = $pause->test_reindex;

  $result->assert_index_updated;

  $result->package_list_ok(
    [
      { package => 'xform::rollout', version => '2.00'  },
    ],
  );

  $result->email_ok(
    [
      { subject => 'PAUSE indexer report OPRIME/xform-rollout-2.00.tar.gz' },
    ],
  );
};

subtest "case mismatch, authorized for original, desc. version" => sub {
  # Don't be tricked by case mismatch into indexing something we shouldn't.
  # Moreover, don't report that the problem is the case change, which might be
  # authorized, when the problem is the descending version. -- rjbs, 2019-04-26
  my $pause = PAUSE::TestPAUSE->init_new;

  $pause->upload_author_fake(OPRIME => 'XForm-Rollout-1.00');

  $pause->test_reindex->package_list_ok(
    [
      { package => 'XForm::Rollout', version => '1.00'  },
    ],
  );

  $pause->upload_author_fake(OPRIME => 'xform-rollout-0.99');

  my $result = $pause->test_reindex;

  $result->package_list_ok(
    [
      { package => 'XForm::Rollout', version => '1.00'  },
    ],
  );

  $result->email_ok(
    [
      { subject => 'Failed: PAUSE indexer report OPRIME/xform-rollout-0.99.tar.gz',
        callbacks => [
          sub {
            like(
              $_[0]->{email}->as_string,
              qr/has\s+a\s+higher\s+version/,
              "email looks right",
            );
          }
        ],
      },
      { subject => 'PAUSE upload indexing error' },
    ],
  );
};

subtest "sometimes, provides fields are empty" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;

  # Key points:
  #   1. dist version 0.50
  #   2. meta provides has...
  #     a. package Provides::NoFile in a named file with version 1.5
  #     b. package Provides::NoFile::Nowhere with an undef file entry
  $pause->upload_author_file(MYSTERIO => 'corpus/Provides-NoFile-0.50.tar.gz');

  my $result = $pause->test_reindex;

  $result->package_list_ok(
    [
      { package => 'Provides::NoFile', version => 1.5 },
    ],
  );

  $result->perm_list_ok(
    {
      'Provides::NoFile'  => { f => 'MYSTERIO' },
    }
  );
};

done_testing;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
