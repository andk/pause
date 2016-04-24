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

subtest "do not index bare .pm but report rejection" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/dot-pm/authors');

  my $result = $pause->test_reindex;

  $pause->file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  $result->email_ok(
    [
      { subject => 'Failed: PAUSE indexer report OPRIME/Matrix.pm.gz' },
    ],
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

sub refused_index_test {
  my ($code) = @_;

  sub {
    my $pause = PAUSE::TestPAUSE->init_new;

    my $db_file = File::Spec->catfile($pause->db_root, 'mod.sqlite');
    my $dbh = DBI->connect(
      'dbi:SQLite:dbname=' . $db_file,
      undef,
      undef,
    ) or die "can't connect to db at $db_file: $DBI::errstr";

    $code->($dbh);
    $pause->import_author_root('corpus/mld/001/authors');
    my $result = $pause->test_reindex;

    $result->package_list_ok(
      [
        { package => 'Hall::MtKing',   version => '0.01'  },
        { package => 'Jenkins::Hack',  version => '0.11'  },
        { package => 'Mooooooose',     version => '0.01'  },
        { package => 'XForm::Rollout', version => '1.00'  },
        { package => 'Y',              version => 2       },
      ],
    );

    my $file = $pause->tmpdir->subdir(qw(cpan modules))->file('06perms.txt');
  };
};

subtest "cannot steal a library when primeur+perms exist" => refused_index_test(sub {
  my ($dbh) = @_;
  $dbh->do("INSERT INTO primeur (package, userid) VALUES ('Bug::Gold','ATRION')")
    or die "couldn't insert!";
  $dbh->do("INSERT INTO perms   (package, userid) VALUES ('Bug::Gold','ATRION')")
    or die "couldn't insert!";
});

subtest "cannot steal a library when only primeur exists" => refused_index_test(sub {
  my ($dbh) = @_;
  $dbh->do("INSERT INTO primeur (package, userid) VALUES ('Bug::Gold','ATRION')")
    or die "couldn't insert!";
});

subtest "cannot steal a library when only perms exist" => refused_index_test(sub {
  my ($dbh) = @_;
  $dbh->do("INSERT INTO perms (package, userid) VALUES ('Bug::Gold','ATRION')")
    or die "couldn't insert!";
});

subtest "cannot steal a library when only mods exist" => refused_index_test(sub {
  my ($dbh) = @_;
  $dbh->do("INSERT INTO mods (modid, userid) VALUES ('Bug::Gold','ATRION')")
    or die "couldn't insert!";
});

subtest "do not index if meta has release_status <> stable" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/002/authors');

  my $result = $pause->test_reindex;

  $result->email_ok(
    [
      { subject => 'PAUSE indexer report MERCKX/Mooooooose-0.02.tar.gz' },
      { subject => 'PAUSE indexer report OOOPPP/Jenkins-Hack-0.12.tar.gz' },
      { subject => 'PAUSE indexer report OPRIME/XForm-Rollout-1.01.tar.gz' },
    ],
  );

  $pause->file_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  $pause->import_author_root('corpus/mld/unstable/authors');

  $result = $pause->test_reindex;

  $pause->file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  $result->package_list_ok(
    [
      { package => 'Jenkins::Hack',  version => '0.12'  },
      { package => 'Jenkins::Hack2', version => '0.12'  },
      { package => 'Mooooooose',     version => '0.02'  },
      { package => 'Mooooooose::Role', version => '0.02'  },
      { package => 'XForm::Rollout', version => '1.01'  },
    ],
  );

  $result->email_ok(
    [
      {
        subject => 'Failed: PAUSE indexer report RJBS/fewer-0.202.tar.gz',
        callbacks => [
          sub {
            like(
              $_[0]{email}->get_body,
              qr/META release_status is not stable/,
              "skip report includes expected text",
            );
          }
        ],
      },
    ],
  );
};

subtest "warn when pkg and module match only case insensitively" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/002/authors');
  $pause->import_author_root('corpus/mld/pkg-mod-case/authors');

  my $result = $pause->test_reindex;

  $result->package_list_ok(
    [
      { package => 'Fewer',          version => '0.202' },
      { package => 'Jenkins::Hack',  version => '0.12'  },
      { package => 'Jenkins::Hack2', version => '0.12'  },
      { package => 'Mooooooose',     version => '0.02'  },
      { package => 'Mooooooose::Role', version => '0.02'  },
      { package => 'More',           version => '0.202' },
      { package => 'XForm::Rollout', version => '1.01'  },
    ],
  );

  $result->email_ok(
    [
      { subject => 'PAUSE indexer report MERCKX/Mooooooose-0.02.tar.gz' },
      { subject => 'PAUSE indexer report OOOPPP/Jenkins-Hack-0.12.tar.gz' },
      { subject => 'PAUSE indexer report OPRIME/XForm-Rollout-1.01.tar.gz' },
      { subject => 'PAUSE indexer report RJBS/fewer-0.202.tar.gz',
        callbacks => [
          sub {
            like(
              $_[0]{email}->get_body,
              qr/Capitalization of package \(Fewer\)/,
              "warning about Fewer v. fewer",
            );
          },
          sub {
            like(
              $_[0]{email}->get_body,
              qr/Capitalization of package \(More\)/,
              "warning about More v. more",
            );
          },
        ]
      },
    ],
  );
};

subtest "(package NAME VERSION BLOCK) and (package NAME BLOCK)" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/pkg-block/authors');

  my $result = $pause->test_reindex;

  $result->package_list_ok(
    [
      { package => 'Pkg::Name',             version => '1.000' },
      { package => 'Pkg::NameBlock',        version => '1.000' },
      { package => 'Pkg::NameVersion',      version => '1.000' },
      { package => 'Pkg::NameVersionBlock', version => '1.000' },
    ],
  );

  $result->email_ok(
    [
      { subject => 'PAUSE indexer report RJBS/Pkg-Name-1.000.tar.gz' },
    ],
  );
};

subtest "check various forms of version" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/bad-version/authors');
  my $result = $pause->test_reindex;

  $pause->file_updated_ok(
    $result->tmpdir
           ->file(qw(cpan modules 02packages.details.txt.gz)),
    "our indexer indexed",
  );

  # VVVVVV          - just fine!  index it
  # VVVVVV::Bogus   - utterly busted, give up
  # VVVVVV::Dev     - has an underscore!  do not index
  # VVVVVV::Lax     - just fine!  index it
  # VVVVVV::VString - version.pm can't handle what we pull out of it

  $result->package_list_ok(
    [
      { package => 'VVVVVV',          version => '6.666'  },
      # { package => 'VVVVVV::Bogus',   version => '6.666june6' },
      # { package => 'VVVVVV::Dev',     version => '6.66_6'     },
      { package => 'VVVVVV::Lax',     version => '6.006006'  },
      # { package => 'VVVVVV::VString', version => 'v6.6.6'    },
    ],
  );

  $result->email_ok(
    [
      { subject => 'PAUSE indexer report RJBS/VVVVVV-6.666.tar.gz' },
    ],
  );
};

subtest "check overlong versions" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/long-version/authors');
  my $result = $pause->test_reindex;

  $pause->file_not_updated_ok(
    $result->tmpdir
           ->file(qw(cpan modules 02packages.details.txt.gz)),
    "there were no things to update",
  );

  my $etoolong = sub {
    like(
      $_[0]{email}->get_body,
      qr/Version string exceeds maximum allowed length/,
      "email contains ELONGVERSION string",
    );
  };

  $result->email_ok(
    [
      {
        subject  => 'Failed: PAUSE indexer report RJBS/VTooLong-1.2345678901234567.tar.gz',
        callbacks => [ $etoolong ],
      },
      {
        subject   => 'Upload Permission or Version mismatch',
        callbacks => [ $etoolong ],
      },
    ],
  );
};

subtest "check perl6 distribution indexing" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/perl6/authors');
  my $result = $pause->test_reindex;

  $result->p6dists_ok(
    [
      { name => 'Inline', ver => '1.1' },
    ],
  );
};

done_testing;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
