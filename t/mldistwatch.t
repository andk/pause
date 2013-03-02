use strict;
use warnings;

use lib 't/lib';

use Email::Sender::Transport::Test;
$ENV{EMAIL_SENDER_TRANSPORT} = 'Test';

use File::Copy::Recursive qw(dircopy);
use File::Path qw(make_path);
use File::Spec;
use PAUSE;
use PAUSE::TestPAUSE;

use Test::Deep;
use Test::More;

my $pause = PAUSE::TestPAUSE->new({
  author_root => 'corpus/mld/001/authors',
});

my $modules_dir = $pause->tmpdir->subdir(qw(cpan modules));
make_path $modules_dir->stringify;
my $index_06 = $modules_dir->file(qw(06perms.txt.gz));

{
  File::Copy::copy('corpus/empty.txt.gz', $index_06->stringify)
    or die "couldn't set up bogus 06perms: $!";
}

subtest "first indexing" => sub {
  my $result = $pause->test_reindex;

  ok(
    -e $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "our indexer indexed",
  );

  my @want = (
    { package => 'Bug::Gold',      version => '9.001' },
    { package => 'Hall::MtKing',   version => '0.01'  },
    { package => 'XForm::Rollout', version => '1.00'  },
    { package => 'Y',              version => 2       },
  );

  subtest "tests with the data in the modules db" => sub {
    my $pkg_rows = $result->connect_mod_db->selectall_arrayref(
      'SELECT * FROM packages ORDER BY package, version',
      { Slice => {} },
    );

    cmp_deeply(
      $pkg_rows,
      [ map {; superhashof($_) } @want ],
      "we db-inserted exactly the dists we expected to",
    );
  };

  subtest "tests with the parsed 02packages data" => sub {
    my $p = $result->packages_data;

    my @packages = sort { $a->package cmp $b->package } $p->packages;

    cmp_deeply(
      \@packages,
      [ map {; methods(%$_) } @want ],
      "we built exactly the 02packages we expected",
    );
  };

  subtest "test 06perms.txt" => sub {
    my $index_06 = $modules_dir->file(qw(06perms.txt.gz));
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
    is(@data, 4, "there are 4 lines of data in 06perms");
  };

  # PAUSE indexer report OPRIME/Bug-Gold-9.001.tar.gz
  # PAUSE indexer report OPRIME/XForm-Rollout-1.00.tar.gz
  # PAUSE indexer report XYZZY/Hall-MtKing-0.01.tar.gz
  # PAUSE indexer report XYZZY/Y-2.tar.gz

  subtest "tests for the emails we sent out" => sub {
    my @deliveries = sort {
      $a->{email}->get_header('Subject') cmp $b->{email}->get_header('Subject')
    } Email::Sender::Simple->default_transport->deliveries;

    my @subj_want = (
      'PAUSE indexer report OPRIME/Bug-Gold-9.001.tar.gz',
      'PAUSE indexer report OPRIME/XForm-Rollout-1.00.tar.gz',
      'PAUSE indexer report XYZZY/Hall-MtKing-0.01.tar.gz',
      'PAUSE indexer report XYZZY/Y-2.tar.gz',
    );

    is_deeply(
      [ map {; $_->{email}->get_header('Subject') } @deliveries ],
      \@subj_want,
      "we sent mail with the right subjects",
    );
  };

  subtest "meagre git tests" => sub {
    ok(
      -e $result->tmpdir->file('git/.git/refs/heads/master'),
      "we now have a master commit",
    );
  };
};

Email::Sender::Simple->default_transport->clear_deliveries;

subtest "reindexing" => sub {
  {
    # XXX: put this all into a TestPAUSE method for update_contents or
    # something -- rjbs, 2013-03-02
    my $tmpdir = $pause->tmpdir;
    my $cpan_root = File::Spec->catdir($tmpdir, 'cpan');
    my $ml_root = File::Spec->catdir($cpan_root, qw(authors id));
    make_path( File::Spec->catdir($cpan_root, 'modules') );
    dircopy('corpus/mld/002/authors', $ml_root);
  }

  my $result = $pause->test_reindex;

  ok(
    -e $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "our indexer indexed",
  );

  my @want = (
    { package => 'Bug::Gold',      version => '9.001' },
    { package => 'Hall::MtKing',   version => '0.01'  },
    { package => 'XForm::Rollout', version => '1.01'  },
    { package => 'Y',              version => 2       },
  );

  subtest "tests with the data in the modules db" => sub {
    my $pkg_rows = $result->connect_mod_db->selectall_arrayref(
      'SELECT * FROM packages ORDER BY package, version',
      { Slice => {} },
    );

    cmp_deeply(
      $pkg_rows,
      [ map {; superhashof($_) } @want ],
      "we db-inserted exactly the dists we expected to",
    );
  };

  subtest "tests with the parsed 02packages data" => sub {
    my $p = $result->packages_data;

    my @packages = sort { $a->package cmp $b->package } $p->packages;

    cmp_deeply(
      \@packages,
      [ map {; methods(%$_) } @want ],
      "we built exactly the 02packages we expected",
    );
  };

  subtest "tests for the emails we sent out" => sub {
    my @deliveries = sort {
      $a->{email}->get_header('Subject') cmp $b->{email}->get_header('Subject')
    } Email::Sender::Simple->default_transport->deliveries;

    my @subj_want = (
      'PAUSE indexer report OPRIME/XForm-Rollout-1.01.tar.gz',
    );

    is_deeply(
      [ map {; $_->{email}->get_header('Subject') } @deliveries ],
      \@subj_want,
      "we sent mail with the right subjects",
    );
  };
};

subtest "case mismatch" => sub {
  {
    # XXX: put this all into a TestPAUSE method for update_contents or
    # something -- rjbs, 2013-03-02
    my $tmpdir = $pause->tmpdir;
    my $cpan_root = File::Spec->catdir($tmpdir, 'cpan');
    my $ml_root = File::Spec->catdir($cpan_root, qw(authors id));
    make_path( File::Spec->catdir($cpan_root, 'modules') );
    dircopy('corpus/mld/002/authors', $ml_root);
  }

  my $result = $pause->test_reindex;

  ok(
    -e $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "our indexer indexed",
  );

  my @want = (
    { package => 'Bug::Gold',      version => '9.001' },
    { package => 'Hall::MtKing',   version => '0.01'  },
    { package => 'XForm::Rollout', version => '1.01'  },
    { package => 'Y',              version => 2       },
  );

  subtest "tests with the data in the modules db" => sub {
    my $pkg_rows = $result->connect_mod_db->selectall_arrayref(
      'SELECT * FROM packages ORDER BY package, version',
      { Slice => {} },
    );

    cmp_deeply(
      $pkg_rows,
      [ map {; superhashof($_) } @want ],
      "we db-inserted exactly the dists we expected to",
    );
  };

  subtest "tests with the parsed 02packages data" => sub {
    my $p = $result->packages_data;

    my @packages = sort { $a->package cmp $b->package } $p->packages;

    cmp_deeply(
      \@packages,
      [ map {; methods(%$_) } @want ],
      "we built exactly the 02packages we expected",
    );
  };

  subtest "tests for the emails we sent out" => sub {
    my @deliveries = sort {
      $a->{email}->get_header('Subject') cmp $b->{email}->get_header('Subject')
    } Email::Sender::Simple->default_transport->deliveries;

    my @subj_want = (
      'PAUSE indexer report OPRIME/XForm-Rollout-1.01.tar.gz',
    );

    is_deeply(
      [ map {; $_->{email}->get_header('Subject') } @deliveries ],
      \@subj_want,
      "we sent mail with the right subjects",
    );
  };
};

done_testing;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
