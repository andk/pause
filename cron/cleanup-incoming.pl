#!/usr/local/bin/perl

use FindBin;
use lib "$FindBin::Bin/../lib";
use PAUSE ();
use DBI;
use File::Spec;

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
  if (0 && $dirent =~ /^(\d+)\.(\d+)$/) { # these come often, but I could not decipher
    open my $fh, $absdirent or die "Could not open $absdirent: $!";
    local $/;
    my $str = <$fh>;
    substr($str,100*1024) = "" if length($str)> 100*1024;
    require Data::Dumper;
    warn sprintf "content[%s]\n", Data::Dumper::Dumper($str);
  }
  unlink $absdirent or die "Could not unlink $absdirent: $!";
  warn "unlinked $absdirent ($size)\n";
}
closedir DIR;
