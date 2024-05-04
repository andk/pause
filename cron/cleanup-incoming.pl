#!/home/pause/.plenv/shims/perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use PAUSE ();
use DBI;
use File::Spec;

use PAUSE::Logger '$Logger' => { init => {
  ident     => 'pause-cleanup-incoming',
  facility  => 'daemon',
} };

my $incdir = File::Spec->canonpath($PAUSE::Config->{INCOMING_LOC});

my $dbh = DBI->connect(
                       $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
                       $PAUSE::Config->{MOD_DATA_SOURCE_USER},
                       $PAUSE::Config->{MOD_DATA_SOURCE_PW},
                       { RaiseError => 1 }
                      );

my $sth = $dbh->prepare("SELECT * FROM uris where uri=?");

opendir DIR, $incdir or die;
for my $dirent (readdir DIR) {
  next if $dirent =~ /^\.(|\.|message)\z/;
  my $absdirent = File::Spec->catfile($incdir,$dirent);
  next unless -f $absdirent;
  next if -M $absdirent < 1/24;
  $sth->execute($dirent);
  next if $sth->rows > 0;
  if ($dirent =~ /-withoutworldwriteables/) {
      my $representing = $dirent;
      $representing =~ s/-withoutworldwriteables//;
      $sth->execute($representing);
      next if $sth->rows > 0;
  }
  my $size = -s $absdirent;

  unlink $absdirent or die "Could not unlink $absdirent: $!";
  $Logger->log("unlinked $absdirent ($size)");
}
closedir DIR;
