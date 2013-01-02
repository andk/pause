#!/usr/local/bin/perl

use FindBin;
use lib "$FindBin::Bin/../lib";
use PAUSE ();

$ENV{LANG} = "C";
my $target = "$PAUSE::Config->{FTPPUB}/modules/";
open my $fh, "-|", "rsync -av $FindBin::Bin/../htdocs/0*.html $target" or die "Could not fork: $!";
while (<$fh>) {
    next if /^building file list/;
    next if /^sent\s.+received/;
    last if /^wrote \d+/;
    last if /^total size is/;
    chomp;
    next unless -e "$target/$_";
    PAUSE::newfile_hook("$target/$_");
}
