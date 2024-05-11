use strict;
use warnings;

use 5.10.1;
use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE

use File::Spec;
use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

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

done_testing;
