
my @time = gmtime;
die "Old cronjob" unless $time[5] eq "103";

use Net::FTP;
my $ftp = Net::FTP->new("ftp.funet.fi");
$ftp->login("anonymous","k\@pause.perl.org");
$ftp->cwd("/pub/languages/perl/CPAN/modules") or die;
($_) = grep /02packages.details.txt.gz/, $ftp->dir;
@l = split;
my $statusfile = "/var/run/netreport/funet_broken.status";
if ("@l[5,6,7]" eq "Feb 10 14:55"){
  open my $fh, ">", $statusfile;
} else {
  unlink $statusfile;
}
