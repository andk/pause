use strict;
use warnings;

use v5.36.0;
use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE

use File::Spec;
use PAUSE;
use PAUSE::TestPAUSE;
use Process::Status;

use Test::More;

subtest "do not index bare .pm but report rejection" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/dot-pm/authors');

  my $result = $pause->test_reindex;

  $result->assert_index_not_updated;

  $result->email_ok(
    [
      { subject => 'Failed: PAUSE indexer report OPRIME/Matrix.pm.gz' },
    ],
  );
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
  $dbh->do("INSERT INTO primeur (package, lc_package, userid) VALUES ('Bug::Gold','bug::gold','ATRION')")
    or die "couldn't insert!";
});

subtest "cannot steal a library when only perms exist" => refused_index_test(sub {
  my ($pause, $dbh) = @_;
  $dbh->do("INSERT INTO perms (package, lc_package, userid) VALUES ('Bug::Gold','bug::gold','ATRION')")
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
    $dbh->do("INSERT INTO perms (package, lc_package, userid) VALUES ('Jenkins::Hack2','jenkins::hack2','ATRION')")
      or die "couldn't insert!";
  },
});

subtest "do not index if meta has release_status <> stable" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->upload_author_fake(OPRIME => 'XForm-Rollout-1.202');
  $pause->upload_author_fake(OPRIME => 'Pie-Eater-1.23');

  {
    my $result = $pause->test_reindex;
    $result->assert_index_updated;

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
  $result->assert_index_updated;

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
  $result->assert_index_updated;

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
              qr/package: Fewer\s+WARNING: Capitalization of package/,
              "warning about Fewer v. fewer",
            );
          },
          sub {
            like(
              $_[0]{email}->get_body,
              qr/package: More\s+WARNING: Capitalization of package/,
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
  $pause->upload_author_fake(RJBS => {
    name      => 'Pkg-Name',
    version   => '1.000',
    packages  => [
      'Pkg::Name'             => { version => '1.000' },
      'Pkg::NameBlock'        => { version => '1.000', layout => { style => 'block' } },
      'Pkg::NameVersion'      => { version => '1.000', layout => { version => 'inline' } },
      'Pkg::NameVersionBlock' => { version => '1.000', layout => { style => 'block', version => 'inline' } },
    ]
  });

  my $result = $pause->test_reindex;
  $result->assert_index_updated;

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
  $pause->upload_author_fake(RJBS => {
    name      => 'VVVVVV',
    version   => '6.666',
    packages  => [
      'VVVVVV'          => { version => '6.666'      },
      'VVVVVV::Bogus'   => { version => '6.666june6' },
      'VVVVVV::Dev'     => { version => '6.66_6'     },
      'VVVVVV::Lax'     => { version => '6.006006'   },
      'VVVVVV::VString' => { version => 'v6.6.6', layout => { version => 'our-literal' } },
    ]
  });

  my $result = $pause->test_reindex;
  $result->assert_index_updated;

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

subtest "version assigned to a blob as a ref" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->upload_author_fake(LUNATIC => 'Globby-Version-1.234.tar.gz', {
    append => [
      {
        file => "lib/Globby/Version/Example.pm",
        content => <<'EOT',
use strict;
use warnings;
package Globby::Version::Example;
*VERSION = \'0.003';
1;
EOT
      }
    ],
  });

  my $result = $pause->test_reindex;
  $result->assert_index_updated;

  $result->package_list_ok([
    { package => 'Globby::Version',           version => '1.234'  },
    { package => 'Globby::Version::Example',  version => '0.003'  }
  ]);

  $result->perm_list_ok({
    'Globby::Version' => { f => 'LUNATIC' },
    'Globby::Version::Example' => { f => 'LUNATIC' },
  });
};

subtest "check overlong versions" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->upload_author_fake(RJBS => {
    name    => 'VTooLong',
    version => '1.2345678901234567',
    packages => [ qw( VTooLong ) ],
  });

  my $result = $pause->test_reindex;
  $result->assert_index_not_updated;

  my $etoolong = sub {
    like(
      $_[0]{email}->object->body_str,
      qr/version string was too long/,
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

subtest "version is not a lax version string" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->upload_author_fake(MONSTER => 'Hex-Version-1.234.tar.gz', {
    append => [
      {
        file => "lib/Hex/Version/NoJoke.pm",
        content => <<'EOT',
use strict;
use warnings;
package Hex::Version::NoJoke;
our $VERSION = '0x1p-1';
1;
EOT
      }
    ],
  });

  my $result = $pause->test_reindex;

  $result->package_list_ok([
    { package => 'Hex::Version', version => '1.234'  },
  ]);

  $result->logged_event_like(
    qr/error with version/,
    "0x1p-1 is a bad version",
  );
};

subtest "case-changing imports" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;

  $pause->add_first_come(FCOME  => 'Foo::Bar');
  $pause->add_first_come(FCOME  => 'Foo::Bar::Baz');
  $pause->add_comaint(   CMAINT => 'Foo::Bar');
  $pause->add_comaint(   CMAINT => 'Foo::Bar::Baz');

  subtest "first step: initial upload" => sub {
    {
      $pause->upload_author_fake(FCOME => {
        name    => 'Foo-Bar',
        version => '0.001',
        packages => [ qw( Foo::Bar Foo::Bar::Baz ) ],
      });

      my $result = $pause->test_reindex;
      $result->assert_index_updated;

      $result->package_list_ok([
        { package => 'Foo::Bar',      version => '0.001'  },
        { package => 'Foo::Bar::Baz', version => '0.001'  }
      ]);

      $result->perm_list_ok({
        'Foo::Bar'      => { f => 'FCOME', c => ['CMAINT'] },
        'Foo::Bar::Baz' => { f => 'FCOME', c => ['CMAINT'] },
      });
    }

    {
      $pause->upload_author_fake(FCOME => {
        name    => 'Foo-Bar',
        version => '0.002',
        packages => [ qw( foo::bar foo::bar::baz ) ],
      });

      my $result = $pause->test_reindex;
      $result->assert_index_updated;

      $result->package_list_ok([
        { package => 'foo::bar',      version => '0.002'  },
        { package => 'foo::bar::baz', version => '0.002'  }
      ]);

      $result->perm_list_ok({
        'foo::bar'      => { f => 'FCOME', c => ['CMAINT'] },
        'foo::bar::baz' => { f => 'FCOME', c => ['CMAINT'] },
      });
    }
  };
};

subtest "check perl6 distribution indexing" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/perl6/authors');
  my $result = $pause->test_reindex;

  $result->assert_index_not_updated("p5 index not updated on p6 upload");

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

  $dbh->do("INSERT INTO packages ('package','lc_package','version','dist','status','file') VALUES ('Bug::Gold','bug::gold','1.001','O/OP/OPRIME/Bug-Gold-1.001.tar.gz','index','notexists')");
  $dbh->do("INSERT INTO packages ('package','lc_package','version','dist','status','file') VALUES ('Bug::gold','bug::gold','0.001','O/OP/OPRIME/Bug-gold-0.001.tar.gz','index','notexists')");

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

subtest "we should not identify version comparison as assignment" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->upload_author_fake(PERSON => 'Version-Cmp-1.234.tar.gz', {
    append => [
      {
        file => "lib/Version/Cmp/Example.pm",
        content => <<'EOT',
use strict;
use warnings;
package Version::Cmp::Example;
1 if $Version::Cmp::Example::VERSION >= 2.0;
$VERSION = '0.003';
1;
EOT
      }
    ],
  });

  my $result = $pause->test_reindex;
  $result->assert_index_updated;

  $result->package_list_ok([
    { package => 'Version::Cmp',           version => '1.234'  },
    { package => 'Version::Cmp::Example',  version => '0.003'  }
  ]);

  $result->perm_list_ok({
    'Version::Cmp'          => { f => 'PERSON' },
    'Version::Cmp::Example' => { f => 'PERSON' },
  });
};

subtest "we should ignore the BOM at the start of a file" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  my $BOM = "\x00\x00\xfe\xff";
  $pause->upload_author_fake(DANKOGAI => 'Lingua-JA-Numbers-0.05.tar.gz', {
    append => [
      {
        file => "lib/Lingua/JA/Numbers.pm",
        content => $BOM . <<'EOT',
package Lingua::JA::Numbers;

use 5.008001;
use strict;
use warnings;
use utf8;

our $VERSION = sprintf "%d.%02d", q$Revision: 0.5 $ =~ /(\d+)/g;
1;
EOT
      }
    ],
  });

  my $result = $pause->test_reindex;
  $result->assert_index_updated;

  $result->package_list_ok([
    { package => 'Lingua::JA::Numbers', version => '0.05'  },
  ]);

  $result->perm_list_ok({
    'Lingua::JA::Numbers' => { f => 'DANKOGAI' },
  });
};

subtest "do not index dists without META file" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->upload_author_fake(PERSON => 'Not-Very-Meta-1.234.tar.gz', {
    omitted_files => [ qw( META.yml META.json ) ],
  });

  my $result = $pause->test_reindex;
  $result->assert_index_not_updated;

  my $nometa = sub {
    like(
      $_[0]{email}->object->body_str,
      qr/\Qno META.yml or META.json found/,
      "email contains ENOMETAFILE string",
    );
  };

  $result->email_ok(
    [
      {
        subject  => 'Failed: PAUSE indexer report PERSON/Not-Very-Meta-1.234.tar.gz',
        callbacks => [ $nometa ],
      },
    ],
  );
};

subtest "do not index dists with trial versions" => sub {
  for my $test (
    { desc => "low line in version", munger => sub { $_[0] =~ s/22/2_2/r } },
    { desc => "TRIAL in version",    munger => sub { $_[0] =~ s/22/22-TRIAL/r } },
  ) {
    subtest $test->{desc} => sub {
      my $pause = PAUSE::TestPAUSE->init_new;

      # Module::Faker will give us a bit of grief for uploading a file called
      # 1.2_2 because it wants to set META release status to stable, and the
      # low line is in conflict with that.  Rather than muck about making this
      # permissible, I'm going to write out the archive, then rename it before
      # indexing.
      my $old_name = $pause->upload_author_fake(PERSON => 'Just-Testing-1.22.tar.gz');
      my $new_name = $test->{munger}->($old_name);

      die "test munger turned old name into old name!"
        if $old_name eq $new_name;

      rename($old_name, $new_name) or die "can't rename $old_name: $!";

      my $result = $pause->test_reindex;

      $result->assert_index_not_updated;

      $result->logged_event_like(
        qr{\Qtrial-release version},
        "we do not index trial-like filenames",
      );
    };
  }
};

subtest "updates to existing packages " => sub {
  my $pause = PAUSE::TestPAUSE->init_new;

  subtest "first version" => sub {
    $pause->upload_author_fake(MTRON => 'Eye-Meeter-1.234.tar.gz');

    my $result = $pause->test_reindex;

    $result->assert_index_updated;

    $result->package_list_ok([
      { package => 'Eye::Meeter', version => '1.234'  },
    ]);
  };

  subtest "second version" => sub {
    $pause->upload_author_fake(MTRON => 'Eye-Meeter-1.235.tar.gz');

    my $result = $pause->test_reindex;

    $result->assert_index_updated;

    $result->package_list_ok([
      { package => 'Eye::Meeter', version => '1.235'  },
    ]);
  };
};

subtest "the notorious version zero" => sub {
  # When we've got two dists both of which provide version 0 (or version
  # undef), we pick the winner by mtime.  I hate this, but I will write a test
  # so that I can someday more confidently forbid anything like this.  Good
  # grief. -- rjbs, 2024-05-11
  my $pause = PAUSE::TestPAUSE->init_new;

  my sub touch_file ($filename, $i) {
    state $base = 1715832000; # May 16, 2024, Philly time
    my $time = $base + $i;
    utime $time, $time, $filename || die "Couldn't touch $filename: $!\n";
  }

  # First, a zero version package.
  # Then, again, but file mtime is older.  We keep the package on file.
  # Then, again, but file mtime is newer.  We switch to the new package.
  my @tests = (
    { desc => "first upload",  offset => 10, dist_v => '1.0', want => '1.0' },
    { desc => "second upload", offset =>  5, dist_v => '1.1', want => '1.0' },
    { desc => "third upload",  offset => 15, dist_v => '1.2', want => '1.2' },
  );

  for my $test (@tests) {
    subtest $test->{desc} => sub {
      my $file = $pause->upload_author_fake(CIPHER => {
        name      => 'Zero',
        version   => $test->{dist_v},
        packages  => [
          'Zero' => { version => '0.000' },
        ],
      });

      touch_file($file, $test->{offset});

      my $result = $pause->test_reindex;

      $result->package_list_ok([
        { package => 'Zero', version => '0.000'  },
      ]);

      my $p = $result->packages_data;

      my $dist = $p->latest_distribution("Zero");
      is($dist->prefix, "C/CI/CIPHER/Zero-$test->{want}.tar.gz", "right dist indexed");
      is($dist->version, $test->{want}, "with the right version");
    };
  }
};

done_testing;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
