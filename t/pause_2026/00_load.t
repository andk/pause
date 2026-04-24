use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/lib", "$FindBin::Bin/../pause_2017/lib";
use Test::PAUSE::Web2026;
use Test::More;
use File::Find;
use Path::Tiny;

note "AppRoot: $Test::PAUSE::Web::AppRoot";

find({wanted => sub {
  my $file = path($File::Find::name);
  my $path = $file->relative("$Test::PAUSE::Web::AppRoot/lib/pause_2026");
  $path =~ s|\.pm$|| or return;
  $path =~ s|/|::|g;
  use_ok($path);
}, no_chdir => 1}, "$Test::PAUSE::Web::AppRoot/lib/pause_2026/PAUSE");

done_testing;

