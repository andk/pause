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

use Test::Deep;
use Test::More;

my $pause = PAUSE::TestPAUSE->new;

$pause->import_author_root('corpus/mld/001/authors');

my $modules_dir = $pause->tmpdir->subdir(qw(cpan modules));
make_path $modules_dir->stringify;
my $index_06 = $modules_dir->file(qw(06perms.txt.gz));

{
  File::Copy::copy('corpus/empty.txt.gz', $index_06->stringify)
    or die "couldn't set up bogus 06perms: $!";
}

sub file_updated_ok {
  my ($filename, $desc) = @_;
  state %last_value;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  unless (-e $filename) {
    return fail("$desc: $filename not updated");
  }

  my ($dev, $ino) = stat $filename;

  my $old = $last_value{ $filename };

  unless (defined $old) {
    $last_value{$filename} = "$dev,$ino";
    return pass("$desc: $filename updated");
  }

  my $ok = ok(
    $old ne "$dev,$ino",
    "$desc: $filename updated",
  );

  $last_value{$filename} = "$dev,$ino";
  return $ok;
}

sub package_list_ok {
  my ($result, $want) = @_;

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
  );
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

  my @deliveries = sort {
    $a->{email}->get_header('Subject') cmp $b->{email}->get_header('Subject')
  } Email::Sender::Simple->default_transport->deliveries;

  Email::Sender::Simple->default_transport->clear_deliveries;

  subtest "emails sent during this run" => sub {
    is(@deliveries, @$want, "as many emails as expected");
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
  }
}

subtest "first indexing" => sub {
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

subtest "case mismatch" => sub {
  $pause->import_author_root('corpus/mld/003/authors');

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

done_testing;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
