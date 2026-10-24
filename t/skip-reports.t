use strict;
use warnings;

use v5.36.0;
use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE

use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

# Some uploads are never indexed, no matter what's inside them, just because of
# their names.  This checks which of those send the uploader a report.  We
# build an ordinary archive, rename it, and index it
sub skipped_upload_reports_ok ($new_basename, $want_subjects) {
  subtest "upload named $new_basename" => sub {
    my $pause = PAUSE::TestPAUSE->init_new;

    my $old_name = $pause->upload_author_fake(PERSON => 'Just-Testing-1.22.tar.gz');
    (my $new_name = $old_name) =~ s{[^/]+\z}{$new_basename};

    rename($old_name, $new_name) or die "can't rename $old_name: $!";

    my $result = $pause->test_reindex;

    $result->assert_index_not_updated;
    $result->email_ok([ map {; { subject => $_ } } @$want_subjects ]);
  };
}

skipped_upload_reports_ok('Just-Testing-1.2_2.tar.gz',     []);
skipped_upload_reports_ok('Just-Testing-1.22-TRIAL.tar.gz', []);
skipped_upload_reports_ok('Just-Testing-1.22.txt', [
  'Failed: PAUSE indexer report PERSON/Just-Testing-1.22.txt',
]);
skipped_upload_reports_ok('perl-5.99.0.tar.gz', [
  'Failed: PAUSE indexer report PERSON/perl-5.99.0.tar.gz',
]);

done_testing;
