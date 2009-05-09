#!/usr/local/bin/perl

use lib "/home/k/pause/lib";
use PAUSE ();

$ENV{LANG} = "C";
my $target = "/home/ftp/pub/PAUSE/modules/";
open my $fh, "-|", "rsync -av /home/k/pause/htdocs/0*.html $target" or die "Could not fork: $!";
while (<$fh>) {
    next if /^building file list/;
    next if /^sent\s.+received/;
    last if /^wrote \d+/;
    last if /^total size is/;
    chomp;
    next unless -e "$target/$_";
    PAUSE::newfile_hook("$target/$_");
}
