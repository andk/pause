
use strict;
use warnings;
my @res;
my %mon = qw(
Jan 01
Feb 02
Mar 03
Apr 04
May 05
Jun 06
Jul 07
Aug 08
Sep 09
Oct 10
Nov 11
Dec 12
);

my(%allus,%alluscpu);

for my $logdir (qw(/var/log/apache/logs /home/rhvar/log/apache/logs)){
  opendir my($dh), $logdir or die;
  my @acc = grep /^acc/, readdir $dh;
  for my $acc (@acc){
    open my($fh), "$logdir/$acc" or die;
    my $hits = 0;
    my $upl = 0;
    my($fday,$lday,%user,%cpupluser);
    while (<$fh>){
      chomp;
      $hits++;
      my($user,
         $day,$status,$ua
        ) = /(?:\S+) \s (?:\S) \s (.+?)
             \s \[ ([^:]+) [^\]]+ \]
             \s \" (?:[^"]|\\")+ \"
             \s (\d+) .*?
             \" ((?: [^"]|\\" )*) \" \z
            /x;
      warn "day=$day, status=$status in $_" unless $status =~ /^\d+$/;
      # warn "day=$day, status=$status ua=$ua in $_" unless $ua =~ /^.+$/;
      next unless $status == 200;
      $fday ||= $day;
      $lday = $day;
      $user{$user}++;
      $allus{$user}++;
      if ($ua =~ /cpan-upload/) {
	$cpupluser{$user}++;
	$alluscpu{$user}++;
	$upl++;
      }
    }
    my $users = keys %user;
    my $cpuplusers = keys %cpupluser;
    printf "acc[%s]fday[%s]lday[%s]hits[%d]
  users[%d]cpuplusers[%d]\n",
                $acc,   $fday,  $lday,   $hits,
        $users,       $cpuplusers;
    for ($fday,$lday) {
      s|(..)/(...)/(....)|$3-$mon{$2}-$1|;
    }
    push @res, [$fday,$lday,$hits,$users,$cpuplusers,$upl];
  }
}

print "
From       To            Hits   Users   Cpan-   Cpan-
                                      upload- uploads
                                        users
";
for (sort {$a->[0] cmp $b->[0]} @res) {
  printf "%s %s %7d %7d %7d %7d\n", @$_;
}

printf "
Over all accesses we have %d users of which %d used cpan-upload
at least once\n\n", scalar keys %allus, scalar keys %alluscpu;

#use Data::Dumper;
#print Dumper(\%alluscpu);
