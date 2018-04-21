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

subtest "retry indexing on db failure" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/009/authors');

  local $PAUSE::Config->{PRE_DB_WORK_CALLBACK} = sub {
    state $x = 1;
    if ($x) {
      $x--, die "dying for diagnostic purposes (x eq $x)\n";
    }
  };

  my $result = $pause->test_reindex;

  $result->package_list_ok(
    [
      { package => 'Jenkins::Hack',         version => '0.14'  },
      { package => 'Jenkins::Hack2',        version => '0.14'  },
      { package => 'Jenkins::Hack::Utils',  version => '0.14'  },
    ],
  );
};

subtest "retry indexing on db failure, only three times" => sub {
  my $pause = PAUSE::TestPAUSE->init_new;
  $pause->import_author_root('corpus/mld/009/authors');

  my $x = 0;
  local $PAUSE::Config->{PRE_DB_WORK_CALLBACK} = sub {
    $x++;
    die "dying for diagnostic purposes (failure $x)\n";
  };

  my $result = $pause->test_reindex;

  is($x, 3, "we tried three times, and no more");

  $pause->file_not_updated_ok(
    $result->tmpdir->file(qw(cpan modules 02packages.details.txt.gz)),
    "did not reindex",
  );

  $result->email_ok(
    [
      { subject => 'Failed: PAUSE indexer report OOOPPP/Jenkins-Hack-0.14.tar.gz',
        callbacks => [
          sub {
            my $index = index $_[0]->{email}->object->body_str,
                           m{ERROR: Database error occurred during index};
            ok($index >= 0, "our indexer report mentions db error");
          },
        ]
      },
      { subject => 'PAUSE upload indexing error' },
    ],
  );
};

done_testing;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
