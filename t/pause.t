use strict;
use warnings;

use 5.10.1;
use lib 't/lib';
use lib 't/privatelib';

use Email::Sender::Transport::Test;
$ENV{EMAIL_SENDER_TRANSPORT} = 'Test';

use File::Spec;
use PAUSE;

use Test::More;

my $dir = __FILE__;
$dir =~ s/pause.t$//;

subtest "PAUSE::filehash md5sum/sha1sum" => sub {
  my $file = "$dir/data/files/somefile.txt";

  my $res = PAUSE::filehash($file);

  is ($res, <<EOF, "filehash response looks good");

  file: t//data/files/somefile.txt
  size: 12 bytes
sha256: f4094f79a8979ace80cc375ab6c1dc640cceee36249ce03928d7e54f7ad66234
EOF

};

done_testing;
