use strict;
use warnings;

use 5.10.1;
use lib 't/lib';

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
   md5: d7e288e2c268b456c3892c3f297dad3a
  sha1: a80338ff32a9b2d4550be8ceb93921f1ce73b343
EOF

};

done_testing;
