use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/lib";
use Test::PAUSE::Web;
use Test::More;
use File::Find;
use Path::Tiny;

note "AppRoot: $Test::PAUSE::Web::AppRoot";

find({wanted => sub {
  my $file = path($File::Find::name);
  my $path = $file->relative("$Test::PAUSE::Web::AppRoot/lib/pause_2025");
  $path =~ s|\.pm$|| or return;
  $path =~ s|/|::|g;
  use_ok($path);
}, no_chdir => 1}, "$Test::PAUSE::Web::AppRoot/lib/pause_2025/PAUSE");

done_testing;

