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

sub init_test_pause {
  my $pause = PAUSE::TestPAUSE->new;

  my $authors_dir = $pause->tmpdir->subdir(qw(cpan authors id));
  make_path $authors_dir->stringify;

  my $modules_dir = $pause->tmpdir->subdir(qw(cpan modules));
  make_path $modules_dir->stringify;
  my $index_06 = $modules_dir->file(qw(06perms.txt.gz));

  {
    File::Copy::copy('corpus/empty.txt.gz', $index_06->stringify)
      or die "couldn't set up bogus 06perms: $!";
  }
  return $pause;
}

my $pause = init_test_pause;
$pause->import_author_root('corpus/mld/001/authors');

my %LAST_FILE_IDENT;
sub file_updated_ok {
  my ($filename, $desc) = @_;
  $desc = defined $desc ? "$desc: " : q{};

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  unless (-e $filename) {
    return fail("$desc$filename not updated");
  }

  my ($dev, $ino) = stat $filename;

  my $old = $LAST_FILE_IDENT{ $filename };

  unless (defined $old) {
    $LAST_FILE_IDENT{$filename} = "$dev,$ino";
    return pass("$desc$filename updated (created)");
  }

  my $ok = ok(
    $old ne "$dev,$ino",
    "$desc$filename updated",
  );

  $LAST_FILE_IDENT{$filename} = "$dev,$ino";
  return $ok;
}

sub file_not_updated_ok {
  my ($filename, $desc) = @_;
  $desc = defined $desc ? "$desc: " : q{};

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $old = $LAST_FILE_IDENT{ $filename };

  unless (-e $filename) {
    return fail("$desc$filename deleted") if $old;
    return pass("$desc$filename not created (thus not updated)");
  }

  my ($dev, $ino) = stat $filename;

  unless (defined $old) {
    $LAST_FILE_IDENT{$filename} = "$dev,$ino";
    return fail("$desc$filename updated (created)");
  }

  my $ok = ok(
    $old eq "$dev,$ino",
    "$desc$filename not updated",
  );

  return $ok;
}

sub package_list_ok {
  my ($result, $want) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $pkg_rows = $result->connect_mod_db->selectall_arrayref(
    'SELECT * FROM packages ORDER BY package, version',
    { Slice => {} },
  );

  cmp_deeply(
    $pkg_rows,
    [ map {; superhashof($_) } @$want ],
    "we db-inserted exactly the dists we expected to",
  ) or diag explain($pkg_rows);


  my $p = $result->packages_data;

  my @packages = sort { $a->package cmp $b->package } $p->packages;

  cmp_deeply(
    \@packages,
    [ map {; methods(%$_) } @$want ],
    "we built exactly the 02packages we expected",
  ) or diag explain(\@packages);
}

sub perm_list_ok {
  my ($result, $want) = @_;

  my $index_06 = $result->tmpdir->subdir(qw(cpan modules))
                 ->file(qw(06perms.txt.gz));

  my $fh;
  our $GZIP = $PAUSE::Config->{GZIP_PATH};
  $pause->with_our_config(sub {
    open $fh, "$GZIP --stdout --uncompress $index_06|"
      or die "can't open $index_06 for reading with gip: $!";
  });

  my (@header, @data);
  while (<$fh>) {
    push(@header, $_), next if 1../^\s*$/;
    push @data, $_;
  }

  # simple is() for now to check for line count
  is(@data, @$want, "there are right number of lines in 06perms");
}

sub email_ok {
  my ($want) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my @deliveries = sort {
    $a->{email}->get_header('Subject') cmp $b->{email}->get_header('Subject')
  } Email::Sender::Simple->default_transport->deliveries;

  Email::Sender::Simple->default_transport->clear_deliveries;

  subtest "emails sent during this run" => sub {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is(@deliveries, @$want, "as many emails as expected: " . @$want);
  };

  for my $test (@$want) {
    my $delivery = shift @deliveries;
    if ($test->{subject}) {
      is(
        $delivery->{email}->get_header('Subject'),
        $test->{subject},
        "Got email: $test->{subject}",
      );
    }

    for (@{ $test->{callbacks} || [] }) {
      local $Test::Builder::Level = $Test::Builder::Level + 1;
      $_->($delivery);
    }
  }
}

subtest "first indexing" => sub {
  my $result = $pause->test_reindex;

  file_updated_ok(
    $result->tmpdir
           ->file(qw(cpan modules 02packages.details.txt.gz)),
    "our indexer indexed",
  );

  file_updated_ok(
    $result->tmpdir
           ->file(qw(cpan modules 03modlist.data.gz)),
    "our indexer indexed",
  );

  package_list_ok(
    $result,
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'XForm::Rollout', version => '1.00'  },
      { package => 'Y',              version => 2       },
    ],
  );

  perm_list_ok(
    $result,
    [ undef, undef, undef, undef ],
  );

  email_ok(
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
  package_list_ok(
    $result,
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

  file_updated_ok(
    $result->tmpdir
           ->file(qw(cpan modules 02packages.details.txt.gz)),
    "our indexer indexed",
  );

  package_list_ok(
    $result,
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  email_ok(
    [
      { subject => 'PAUSE indexer report OPRIME/XForm-Rollout-1.01.tar.gz' },
    ],
  );
};

Email::Sender::Simple->default_transport->clear_deliveries;

subtest "distname/pkgname permission mismatch" => sub {
  $pause->import_author_root('corpus/mld/003/authors');

  my $result = $pause->test_reindex;

  file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  package_list_ok(
    $result,
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  email_ok(
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

  file_not_updated_ok(
    $result->tmpdir
           ->file(qw(cpan modules 02packages.details.txt.gz)),
    "our indexer indexed",
  );

  package_list_ok(
    $result,
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  email_ok(
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

  file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  package_list_ok(
    $result,
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  email_ok(
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

  file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  package_list_ok(
    $result,
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

  file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  package_list_ok(
    $result,
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  email_ok(
    [
      { subject => 'Failed: PAUSE indexer report OPRIME/Bug-Gold-9.002.tar.gz' },
    ],
  );
};

Email::Sender::Simple->default_transport->clear_deliveries;

subtest "distname/pkgname permission check" => sub {
  $pause->import_author_root('corpus/mld/006-distname/authors');

  my $result = $pause->test_reindex;

  file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  package_list_ok(
    $result,
    [
      { package => 'Bug::Gold',      version => '9.001' },
      { package => 'Bug::gold',      version => '0.001' },
      { package => 'Hall::MtKing',   version => '0.01'  },
      { package => 'XForm::Rollout', version => '1.01'  },
      { package => 'Y',              version => 2       },
    ],
  );

  email_ok(
    [
      { subject => 'Failed: PAUSE indexer report OPRIME/Y-3.tar.gz' },
      { subject => 'Upload Permission or Version mismatch' },
    ],
  );
};

Email::Sender::Simple->default_transport->clear_deliveries;

subtest "do not index bare .pm but report rejection" => sub {
  my $pause = init_test_pause;
  $pause->import_author_root('corpus/mld/dot-pm/authors');

  my $result = $pause->test_reindex;

  file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  email_ok(
    [
      { subject => 'Failed: PAUSE indexer report OPRIME/Matrix.pm.gz' },
    ],
  );
};

sub refused_index_test {
  my ($code) = @_;

  sub {
    my $pause = init_test_pause;

    my $db_file = File::Spec->catfile($pause->db_root, 'mod.sqlite');
    my $dbh = DBI->connect(
      'dbi:SQLite:dbname=' . $db_file,
      undef,
      undef,
    ) or die "can't connect to db at $db_file: $DBI::errstr";

    $code->($dbh);
    $pause->import_author_root('corpus/mld/001/authors');
    my $result = $pause->test_reindex;

    package_list_ok(
      $result,
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
  my $pause = init_test_pause;
  $pause->import_author_root('corpus/mld/002/authors');

  my $result = $pause->test_reindex;

  file_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  $pause->import_author_root('corpus/mld/unstable/authors');

  $result = $pause->test_reindex;

  file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  package_list_ok(
    $result,
    [
      { package => 'XForm::Rollout', version => '1.01'  },
    ],
  );

  email_ok(
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
      { subject => 'PAUSE indexer report OPRIME/XForm-Rollout-1.01.tar.gz' },
    ],
  );
};

subtest "warn when pkg and module match only case insensitively" => sub {
  my $pause = init_test_pause;
  $pause->import_author_root('corpus/mld/002/authors');
  $pause->import_author_root('corpus/mld/pkg-mod-case/authors');

  my $result = $pause->test_reindex;

  package_list_ok(
    $result,
    [
      { package => 'Fewer',          version => '0.202' },
      { package => 'More',           version => '0.202' },
      { package => 'XForm::Rollout', version => '1.01'  },
    ],
  );

  email_ok(
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
  my $pause = init_test_pause;
  $pause->import_author_root('corpus/mld/pkg-block/authors');

  my $result = $pause->test_reindex;

  package_list_ok(
    $result,
    [
      { package => 'Pkg::Name',             version => '1.000' },
      { package => 'Pkg::NameBlock',        version => '1.000' },
      { package => 'Pkg::NameVersion',      version => '1.000' },
      { package => 'Pkg::NameVersionBlock', version => '1.000' },
    ],
  );

  email_ok(
    [
      { subject => 'PAUSE indexer report RJBS/Pkg-Name-1.000.tar.gz' },
    ],
  );
};

subtest "check various forms of version" => sub {
  my $pause = init_test_pause;
  $pause->import_author_root('corpus/mld/bad-version/authors');
  my $result = $pause->test_reindex;

  file_updated_ok(
    $result->tmpdir
           ->file(qw(cpan modules 02packages.details.txt.gz)),
    "our indexer indexed",
  );

  # VVVVVV          - just fine!  index it
  # VVVVVV::Bogus   - utterly busted, give up
  # VVVVVV::Dev     - has an underscore!  do not index
  # VVVVVV::Lax     - just fine!  index it
  # VVVVVV::VString - version.pm can't handle what we pull out of it

  package_list_ok(
    $result,
    [
      { package => 'VVVVVV',          version => '6.666'  },
      # { package => 'VVVVVV::Bogus',   version => '6.666june6' },
      # { package => 'VVVVVV::Dev',     version => '6.66_6'     },
      { package => 'VVVVVV::Lax',     version => '6.006006'  },
      # { package => 'VVVVVV::VString', version => 'v6.6.6'    },
    ],
  );

  email_ok(
    [
      { subject => 'PAUSE indexer report RJBS/VVVVVV-6.666.tar.gz' },
    ],
  );
};

done_testing;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
