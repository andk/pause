use strict;
use warnings;

use v5.36.0;
use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE

use Archive::Tar ();
use PAUSE;
use PAUSE::TestPAUSE;

use Test::More;

# Each case here builds an ordinary fake dist, Archive-Layout-1.0, and then
# rewrites the paths inside its archive.  $arg->{rename} gets each path, which
# starts with "Archive-Layout-1.0/", and returns the path to store instead, or
# undef to leave the file out.  If $arg->{dot_entry} is given, it's a mode, and
# the archive also gets a "./" directory entry with that mode, the way
# "tar -czf x.tar.gz ." writes one.
sub archive_layout_ok ($desc, $arg) {
  subtest $desc => sub {
    my $pause = PAUSE::TestPAUSE->init_new;

    my $file = $pause->upload_author_fake(PERSON => 'Archive-Layout-1.0.tar.gz');

    my $tar = Archive::Tar->new($file) or die "can't read $file";
    my $out = Archive::Tar->new;

    if (defined $arg->{dot_entry}) {
      $out->add_data('./', '', {
        type => Archive::Tar::Constant::DIR(),
        mode => $arg->{dot_entry},
      });
    }

    for my $entry ($tar->get_files) {
      my $name = $arg->{rename}->($entry->full_path) // next;
      $out->add_data($name, $entry->get_content, { mode => $entry->mode });
    }

    $out->write($file, Archive::Tar::COMPRESS_GZIP()) or die $out->error;

    my $result = $pause->test_reindex;

    if (my $want = $arg->{indexed}) {
      $result->package_list_ok([ map {; { package => $_ } } @$want ]);

      $result->email_ok([
        { subject => 'PAUSE indexer report PERSON/Archive-Layout-1.0.tar.gz' },
      ]);

      return;
    }

    $result->assert_index_not_updated;

    $result->email_ok([
      {
        subject   => 'Failed: PAUSE indexer report PERSON/Archive-Layout-1.0.tar.gz',
        callbacks => [
          sub {
            like(
              $_[0]{email}->object->body_str,
              qr/does not unpack into a single\s+directory/,
              "report says the archive needs one top-level directory",
            );
          },
        ],
      },
    ]);
  };
}

archive_layout_ok("normal archive", {
  rename  => sub ($path) { $path },
  indexed => [ 'Archive::Layout' ],
});

archive_layout_ok("archive with ./ prefix on its one directory", {
  rename  => sub ($path) { "./$path" },
  indexed => [ 'Archive::Layout' ],
});

archive_layout_ok("archive with ./ entry and its one directory under it", {
  rename    => sub ($path) { "./$path" },
  dot_entry => 0755,
  indexed   => [ 'Archive::Layout' ],
});

# The archive is extracted right into the indexer's work directory, so a "./"
# entry is an entry for the work directory itself.  Its mode must not be
# applied there, or the indexer can lose access to its own work directory.
archive_layout_ok("archive with ./ entry whose mode lacks x bits", {
  rename    => sub ($path) { "./$path" },
  dot_entry => 0644,
  indexed   => [ 'Archive::Layout' ],
});

# A tarbomb that still has its META file at the top level used to be reported
# as having no META file at all, because we look for META inside the expected
# top-level directory.  It should be told what's really wrong.
archive_layout_ok("tarbomb: dist contents at the top level", {
  rename => sub ($path) { $path =~ s{\AArchive-Layout-1\.0/}{}r },
});

archive_layout_ok("tarbomb: dist contents at the top level, under ./", {
  rename    => sub ($path) { $path =~ s{\AArchive-Layout-1\.0/}{./}r },
  dot_entry => 0755,
});

archive_layout_ok("tarbomb: a single file at the top level", {
  rename => sub ($path) {
    $path =~ m{/lib/Archive/Layout\.pm\z} ? 'Layout.pm' : undef
  },
});

done_testing;
