use strict;
use warnings;

use 5.10.1;
use lib 't/lib';

use Email::Sender::Transport::Test;
$ENV{EMAIL_SENDER_TRANSPORT} = 'Test';

use File::Copy::Recursive qw(dircopy);
use File::Path qw(make_path);
use File::Spec;
use PAUSE;
use PAUSE::TestPAUSE;

use Test::Deep qw(cmp_deeply superhashof methods);
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
      { package => 'XForm::Rollout', version => '1.00'  },
      { package => 'Y',              version => 2       },
    ],
  );

  $result->perm_list_ok(
    [ undef, undef, undef, undef ],
  );

  $result->email_ok(
    [
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

Email::Sender::Simple->default_transport->clear_deliveries;

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
      { package => 'XForm::Rollout', version => '1.00'  },
      { package => 'Y',              version => 2       },
    ]
  );
};

Email::Sender::Simple->default_transport->clear_deliveries;

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
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  $result->email_ok(
    [
      { subject => 'PAUSE indexer report OPRIME/XForm-Rollout-1.01.tar.gz' },
    ],
  );
};

Email::Sender::Simple->default_transport->clear_deliveries;

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
              qr/XFR,\s+which\s+you\s+do\s+not\s+have/,
              "email looks right",
            );
          }
        ],
      },
      { subject => 'Upload Permission or Version mismatch' },
    ],
  );
};

Email::Sender::Simple->default_transport->clear_deliveries;

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

Email::Sender::Simple->default_transport->clear_deliveries;

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

Email::Sender::Simple->default_transport->clear_deliveries;

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
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  # TODO: send a report saying 'no perl-X allowed'
};

Email::Sender::Simple->default_transport->clear_deliveries;

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

Email::Sender::Simple->default_transport->clear_deliveries;

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

Email::Sender::Simple->default_transport->clear_deliveries;

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

# XXX
subtest "do not index bare .pm but report rejection" => sub {
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

Email::Sender::Simple->default_transport->clear_deliveries;

subtest "do not index if meta has release_status <> stable" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/002/authors');

  my $result = $pause->test_reindex;

  $result->email_ok(
    [
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
      { package => 'More',           version => '0.202' },
      { package => 'XForm::Rollout', version => '1.01'  },
    ],
  );

  $result->email_ok(
    [
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

subtest "check perl6 distribution indexing" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/perl6/authors');
  my $result = $pause->test_reindex;

  $result->p6dists_ok(
    [
      { name => 'Inline', ver => 'v1.1' },
    ],
  );
};

done_testing;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
