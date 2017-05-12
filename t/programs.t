#!perl -- -*- mode: cperl -*-

use Test::More;
use File::Spec;
use lib 't/lib';
use TestSetup;

sub _f ($) {File::Spec->catfile(split /\//, shift);}

my $Id = q$Id: bap.t 26 2003-02-16 19:01:03Z k $;

my @s = qw(
           bin/paused
           cron/mldistwatch
           cron/cleanup-incoming.pl
          );
for my $dir (qw(bin cron)) {
    opendir my $dh, $dir or die "Could not opendir $dir: $!";
    for my $d (readdir $dh) {
        next unless $d =~ /\.pl$/;
        push @s, "$dir/$d";
    }
}

my $tests_per_loop = 1;
my $plan = scalar @s * $tests_per_loop;
plan tests => $plan;

my $devnull = File::Spec->devnull;
for my $s (1..@s) {
  my $script = _f($s[$s-1]);
  open my $fh, "-|", qq{"$^X" "-Ilib" "-Iblib/privatelib" "-cw" "$script" 2>&1} or die "could not fork: $!";
  while (<$fh>) {
      next if /syntax OK/;
      diag $_;
  }
  my $ret = close $fh;
  ok 1==$ret, "$script:-c:$ret";
}

__END__

