use strict;
use warnings;

use 5.10.1;
use lib 't/lib';
use lib 't/lib/privatelib'; # Stub PrivatePAUSE

use Email::Sender::Transport::Test;
$ENV{EMAIL_SENDER_TRANSPORT} = 'Test';

use File::Spec;
use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

my $pause = PAUSE::TestPAUSE->init_new;
$pause->import_author_root('corpus/mld/001/authors');

subtest "first indexing" => sub {
  my $result = $pause->test_reindex;

  $pause->file_updated_ok(
    $result->tmpdir
           ->file(qw(cpan modules 02packages.details.txt.gz)),
    "our indexer indexed",
  );

  $pause->file_updated_ok(
    $result->tmpdir
           ->file(qw(cpan modules 03modlist.data.gz)),
    "our indexer indexed",
  );

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
      -e $result->tmpdir->file('git/.git/refs/heads/master'),
      "we now have a master commit",
    );
  };

};

subtest "add comaintainer" => sub {

  my $result = $pause->test_reindex;
  my $dbh = $result->connect_mod_db;
  my @comaintainers = (
    [qw/Bug::Gold ATRION/],
    [qw/Jenkins::Hack ONE/],
    [qw/Jenkins::Hack TWO/],
    [qw/Jenkins::Hack2 OOOPPP/],
    [qw/Mooooooose MERCKX/],
    [qw/Mooooooose BOONEN/],
  );
  for my $comaint (@comaintainers)
  {
    $dbh->do("INSERT INTO perms   (package, userid) VALUES (?,?)", {}, @$comaint)
        or die "couldn't insert!";
  }

  $result = $pause->test_reindex;

  $result->perm_list_ok(
    {
      'Bug::Gold'       => { f => 'OPRIME', c => ['ATRION'] },
      'Hall::MtKing'    => { f => 'XYZZY' },
      'Jenkins::Hack'   => { f => 'OOOPPP', c => [qw/ONE TWO/] },
      'Jenkins::Hack2'  => { c => [qw/OOOPPP/] },
      'Mooooooose'      => { f => 'AAARGH', c => [qw/BOONEN MERCKX/] },
      'XForm::Rollout'  => { f => 'OPRIME' },
      'Y',              => { f => 'XYZZY' },
    }
  );
};

subtest "add historic content" => sub {
  $DB::single=1;
  my $result = $pause->test_reindex;
  my $dbh = $result->connect_mod_db;
  $dbh->do("INSERT INTO packages ('package','version','dist','status','file') VALUES ('Bug::gold','0.001','O/OP/OPRIME/Bug-gold-0.001.tar.gz','index','notexists')");
  my $time = time;
  $dbh->do("INSERT INTO distmtimes ('dist','distmtime') VALUES ('O/OP/OPRIME/Bug-gold-0.001.tar.gz','$time')");
  open my $fh, ">", $pause->tmpdir->file(qw(cpan authors id O OP OPRIME Bug-gold-0.001.tar.gz)) or die "Could not open: $!";
  print $fh qq<fake tarball>;
  close $fh or die "Could not close: $!";
  $result = $pause->test_reindex;
  $result->package_list_ok(
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'Jenkins::Hack',  version => '0.11'  },
      { package => 'Mooooooose',     version => '0.01'  },
      { package => 'XForm::Rollout', version => '1.00'  },
      { package => 'Y',              version => 2       },
    ]
  );
};

subtest "reindexing" => sub {
  $pause->import_author_root('corpus/mld/002/authors');

  my $result = $pause->test_reindex;

  $pause->file_updated_ok(
    $result->tmpdir
           ->file(qw(cpan modules 02packages.details.txt.gz)),
    "our indexer indexed",
  );

  $result->package_list_ok(
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'Jenkins::Hack',  version => '0.12'  },
      { package => 'Jenkins::Hack2', version => '0.12'  },
      { package => 'Mooooooose',     version => '0.02'  },
      { package => 'Mooooooose::Role', version => '0.02'  },
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  $result->email_ok(
    [
      { subject => 'PAUSE indexer report MERCKX/Mooooooose-0.02.tar.gz' },
      { subject => 'PAUSE indexer report OOOPPP/Jenkins-Hack-0.12.tar.gz' },
      { subject => 'PAUSE indexer report OPRIME/XForm-Rollout-1.01.tar.gz' },
    ],
  );
};

subtest "distname/pkgname permission mismatch" => sub {
  $pause->import_author_root('corpus/mld/003/authors');

  my $result = $pause->test_reindex;

  $pause->file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  $result->package_list_ok(
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'Jenkins::Hack',  version => '0.12'  },
      { package => 'Jenkins::Hack2', version => '0.12'  },
      { package => 'Mooooooose',     version => '0.02'  },
      { package => 'Mooooooose::Role', version => '0.02'  },
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  $result->email_ok(
    [
      { subject => 'Failed: PAUSE indexer report UMAGNUS/XFR-2.000.tar.gz' ,
        callbacks => [
          sub {
            like(
              $_[0]->{email}->as_string,
              qr/for\s+the\s+package\s+XFR/,
              "email looks right",
            );
          },
          sub {
            like(
              $_[0]->{email}->as_string,
              qr/You\s+appear.*\.pm\s+file.*dist\s+name\s+\(XFR\)/s,
              "email looks right",
            );
          }
        ],
      },
      { subject => 'Upload Permission or Version mismatch' },
    ],
  );
};

subtest "case mismatch, authorized for original" => sub {
  $pause->import_author_root('corpus/mld/004/authors');

  my $result = $pause->test_reindex;

  $pause->file_not_updated_ok(
    $result->tmpdir
           ->file(qw(cpan modules 02packages.details.txt.gz)),
    "our indexer indexed",
  );

  $result->package_list_ok(
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'Jenkins::Hack',  version => '0.12'  },
      { package => 'Jenkins::Hack2', version => '0.12'  },
      { package => 'Mooooooose',     version => '0.02'  },
      { package => 'Mooooooose::Role', version => '0.02'  },
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  $result->email_ok(
    [
      { subject => 'Failed: PAUSE indexer report OPRIME/xform-rollout-2.00.tar.gz' },
      { subject => 'Upload Permission or Version mismatch' },
    ],
  );
};

subtest "case mismatch, authorized for original, desc. version" => sub {
  $pause->import_author_root('corpus/mld/005/authors');

  my $result = $pause->test_reindex;

  $pause->file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  $result->package_list_ok(
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'Jenkins::Hack',  version => '0.12'  },
      { package => 'Jenkins::Hack2', version => '0.12'  },
      { package => 'Mooooooose',     version => '0.02'  },
      { package => 'Mooooooose::Role', version => '0.02'  },
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  $result->email_ok(
    [
      { subject => 'Failed: PAUSE indexer report OPRIME/XForm-Rollout-1.00a.tar.gz',
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
      { subject => 'Upload Permission or Version mismatch' },
    ],
  );
};

subtest "perl-\\d should not get indexed" => sub {
  $pause->import_author_root('corpus/mld/006/authors');

  my $result = $pause->test_reindex;

  $pause->file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  $result->package_list_ok(
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'Jenkins::Hack',  version => '0.12'  },
      { package => 'Jenkins::Hack2', version => '0.12'  },
      { package => 'Mooooooose',     version => '0.02'  },
      { package => 'Mooooooose::Role', version => '0.02'  },
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  # TODO: send a report saying 'no perl-X allowed'
};

subtest "don't allow upload on permissions case conflict" => sub {
  $pause->import_author_root('corpus/mld/007/authors');

  my $result = $pause->test_reindex;

  $pause->file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  $result->package_list_ok(
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'Jenkins::Hack',  version => '0.12'  },
      { package => 'Jenkins::Hack2', version => '0.12'  },
      { package => 'Mooooooose',     version => '0.02'  },
      { package => 'Mooooooose::Role', version => '0.02'  },
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  $result->email_ok(
    [
      { subject => 'Failed: PAUSE indexer report OPRIME/Bug-Gold-9.002.tar.gz' },
    ],
  );
};

subtest "distname/pkgname permission check" => sub {
  $pause->import_author_root('corpus/mld/006-distname/authors');

  my $result = $pause->test_reindex;

  $pause->file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  $result->package_list_ok(
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'Jenkins::Hack',  version => '0.12'  },
      { package => 'Jenkins::Hack2', version => '0.12'  },
      { package => 'Mooooooose',     version => '0.02'  },
      { package => 'Mooooooose::Role', version => '0.02'  },
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  $result->email_ok(
    [
      { subject => 'Failed: PAUSE indexer report OPRIME/Y-3.tar.gz' },
      { subject => 'Upload Permission or Version mismatch' },
    ],
  );
};

subtest "check comaintainers" => sub {

  my $result = $pause->test_reindex;
  TODO: {
    local $TODO = "Default permissions for new modules to be implemented";
    $result->perm_list_ok(
      {
        'Bug::Gold'       => { f => 'OPRIME', c => ['ATRION'] },
        'Hall::MtKing'    => { f => 'XYZZY' },
        'Jenkins::Hack'   => { f => 'OOOPPP', c => [qw/ONE TWO/] },
        'Jenkins::Hack2'  => { f => 'OOOPPP', c => [qw/ONE TWO/] },
        'Mooooooose'      => { f => 'AAARGH' },
        'Mooooooose::Role' => { f => 'AAARGH', c => [qw/MERCKX/] },
        'XForm::Rollout'  => { f => 'OPRIME' },
        'Y',              => { f => 'XYZZY' },
      }
    );
  };
};

subtest "comaint upload" => sub {

  $pause->import_author_root('corpus/mld/008/authors');
  my $result = $pause->test_reindex;
    $result->perm_list_ok(
      {
        'Bug::Gold'       => { f => 'OPRIME', c => ['ATRION'] },
        'Hall::MtKing'    => { f => 'XYZZY' },
        'Jenkins::Hack'   => { f => 'OOOPPP', c => [qw/ONE TWO/] },
        'Jenkins::Hack2'  => { f => 'OOOPPP', c => [qw/ONE TWO/] },
        'Jenkins::Hack::Utils'  => { f => 'OOOPPP', c => [qw/ONE TWO/] },
        'Mooooooose'      => { f => 'AAARGH', c => [qw/BOONEN MERCKX/] },
        'Mooooooose::Role'      => { f => 'AAARGH', c => [qw/BOONEN MERCKX/] },
        'Mooooooose::Trait'      => { f => 'AAARGH', c => [qw/BOONEN MERCKX/] },
        'XForm::Rollout'  => { f => 'OPRIME' },
        'Y',              => { f => 'XYZZY' },
      }
    );
};

subtest "other comaint upload" => sub {

  $pause->import_author_root('corpus/mld/009/authors');
  my $result = $pause->test_reindex;
    $result->perm_list_ok(
      {
        'Bug::Gold'       => { f => 'OPRIME', c => ['ATRION'] },
        'Hall::MtKing'    => { f => 'XYZZY' },
        'Jenkins::Hack'   => { f => 'OOOPPP', c => [qw/ONE TWO/] },
        'Jenkins::Hack2'  => { f => 'OOOPPP', c => [qw/ONE TWO/] },
        'Jenkins::Hack::Utils'  => { f => 'OOOPPP', c => [qw/ONE TWO/] },
        'Mooooooose'      => { f => 'AAARGH', c => [qw/BOONEN MERCKX/] },
        'Mooooooose::Role'      => { f => 'AAARGH', c => [qw/BOONEN MERCKX/] },
        'Mooooooose::Trait'      => { f => 'AAARGH', c => [qw/BOONEN MERCKX/] },
        'XForm::Rollout'  => { f => 'OPRIME' },
        'Y',              => { f => 'XYZZY' },
      }
    );
};
done_testing;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
