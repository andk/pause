#!/usr/bin/perl

use lib "/home/k/pause/lib";
use PAUSE ();

$ENV{LANG} = "C";
open my $fh, "-|", "rsync -av /home/k/pause/htdocs/0*.html /home/ftp/pub/PAUSE/modules/" or die "Could not fork: $!";
while (<$fh>) {
    next if /^building file list/;
    last if /^wrote \d+/;
    last if /^total size is/;
    chomp;
    PAUSE::newfile_hook($_);
}
