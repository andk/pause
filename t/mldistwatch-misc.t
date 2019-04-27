use strict;
use warnings;

use 5.10.1;
use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE

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

subtest "perl-\\d should not get indexed" => sub {
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
  my ($arg) = @_;

  if (ref $arg eq 'CODE') {
    $arg = {
      before  => $arg,
      uploads => [
        OPRIME => 'XForm-Rollout-1.234',
      ],
      want_package_list => [
        { package => 'XForm::Rollout', version => '1.234' },
      ],
    };
  }

  sub {
    my $pause = PAUSE::TestPAUSE->init_new;

    my $db_file = File::Spec->catfile($pause->db_root, 'mod.sqlite');
    my $dbh = DBI->connect(
      'dbi:SQLite:dbname=' . $db_file,
      undef,
      undef,
    ) or die "can't connect to db at $db_file: $DBI::errstr";

    $arg->{before}->($pause, $dbh);

    if ($arg->{uploads}) {
      my @uploads = @{ $arg->{uploads} };
      while (my ($uploader, $upload) = splice @uploads, 0, 2) {
        $pause->upload_author_fake($uploader, $upload);
      }
    }

    my $result = $pause->test_reindex;

    $result->package_list_ok($arg->{want_package_list});

    my $file = $pause->tmpdir->subdir(qw(cpan modules))->file('06perms.txt');
  };
};

subtest "cannot steal a library when primeur+perms exist" => refused_index_test(sub {
  my ($pause) = @_;
  $pause->add_first_come('ATRION', 'Bug::Gold');
});

subtest "cannot steal a library when only primeur exists" => refused_index_test(sub {
  my ($pause, $dbh) = @_;
  $dbh->do("INSERT INTO primeur (package, userid) VALUES ('Bug::Gold','ATRION')")
    or die "couldn't insert!";
});

subtest "cannot steal a library when only perms exist" => refused_index_test(sub {
  my ($pause, $dbh) = @_;
  $dbh->do("INSERT INTO perms (package, userid) VALUES ('Bug::Gold','ATRION')")
    or die "couldn't insert!";
});

subtest "cannot steal a library via copy-main-perms mechanism" => refused_index_test({
  uploads     => [
    HAXOR => {
      name      => 'Jenkins-Hack',
      version   => 0.14,
      packages  => [ qw( Jenkins::Hack Jenkins::Hack2 Jenkins::Hack::Utils ) ],
    },
  ],
  want_package_list => [
    { package => 'Jenkins::Hack',         version => '0.14' },
    { package => 'Jenkins::Hack::Utils',  version => '0.14' },
  ],
  before      => sub {
    my ($pause, $dbh) = @_;
    $dbh->do("INSERT INTO perms (package, userid) VALUES ('Jenkins::Hack2','ATRION')")
      or die "couldn't insert!";
  },
});

subtest "do not index if meta has release_status <> stable" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->upload_author_fake(OPRIME => 'XForm-Rollout-1.202');
  $pause->upload_author_fake(OPRIME => 'Pie-Eater-1.23');

  {
    my $result = $pause->test_reindex;

    $result->email_ok([
      { subject => 'PAUSE indexer report OPRIME/Pie-Eater-1.23.tar.gz' },
      { subject => 'PAUSE indexer report OPRIME/XForm-Rollout-1.202.tar.gz' },
    ]);

    $result->package_list_ok([
      { package => 'Pie::Eater',      version => '1.23'  },
      { package => 'XForm::Rollout',  version => '1.202'  },
    ]);
  }

  $pause->upload_author_fake(OPRIME => 'XForm-Rollout-1.203');
  $pause->upload_author_fake(
    OPRIME => 'Pie-Eater-1.24',
    { release_status => 'unstable' },
  );

  my $result = $pause->test_reindex;

  $result->package_list_ok([
    { package => 'Pie::Eater',      version => '1.23'  },
    { package => 'XForm::Rollout',  version => '1.203'  },
  ]);

  $result->email_ok(
    [
      {
        subject => 'Failed: PAUSE indexer report OPRIME/Pie-Eater-1.24.tar.gz',
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
      { subject => 'PAUSE indexer report OPRIME/XForm-Rollout-1.203.tar.gz' },
    ],
  );
};

subtest "warn when pkg and module match only case insensitively" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;

  $pause->upload_author_fake(RJBS => {
    name      => 'fewer',
    version   => 0.202,
    packages  => [
      More  => { in_file => 'lib/more.pm' },
      Fewer => { in_file => 'lib/fewer.pm' },
    ]
  });

  my $result = $pause->test_reindex;

  $result->package_list_ok(
    [
      { package => 'Fewer', version => '0.202' },
      { package => 'More',  version => '0.202' },
    ],
  );

  $result->email_ok(
    [
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
      $_[0]{email}->object->body_str,
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
        subject   => 'PAUSE upload indexing error',
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

subtest "sort of case-conflicted packages is stable" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;

  my $result = $pause->test_reindex;
  my $dbh = $result->connect_mod_db;

  $dbh->do("INSERT INTO packages ('package','version','dist','status','file') VALUES ('Bug::Gold','1.001','O/OP/OPRIME/Bug-Gold-1.001.tar.gz','index','notexists')");
  $dbh->do("INSERT INTO packages ('package','version','dist','status','file') VALUES ('Bug::gold','0.001','O/OP/OPRIME/Bug-gold-0.001.tar.gz','index','notexists')");

  my $now  = time - 86400;
  my $then = time - 86400*30;

  $dbh->do("INSERT INTO distmtimes ('dist','distmtime') VALUES ('O/OP/OPRIME/Bug-gold-0.001.tar.gz','$then')");
  $dbh->do("INSERT INTO distmtimes ('dist','distmtime') VALUES ('O/OP/OPRIME/Bug-Gold-1.001.tar.gz','$now')");

  for my $fn (qw(Bug-gold-0.001.tar.gz Bug-Gold-1.001.tar.gz)) {
    my $dir = $pause->tmpdir->subdir( qw(cpan authors id O OP OPRIME) );
    $dir->mkpath;

    open my $fh, ">", $dir->file($fn) or die "Could not open: $!";
    print $fh qq<fake tarball>;
    close $fh or die "Could not close: $!";
  }

  $result = $pause->test_reindex;
  $result->package_list_ok(
    [
      { package => 'Bug::Gold',      version => '1.001' },
      { package => 'Bug::gold',      version => '0.001' },
    ]
  );
};

done_testing;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
