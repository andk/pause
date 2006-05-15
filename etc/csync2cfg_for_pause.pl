# $HeadURL: https://pause.perl.org:5460/svn/pause/trunk/etc/csync2.cfg $
# $Id: csync2.cfg 754 2006-04-23 10:14:58Z k $

use strict;
use warnings;
use Getopt::Long;
use DBI;
use File::Basename qw(dirname);
use File::Path qw(mkpath);
use Sys::Hostname;

my $sys_hostname = Sys::Hostname::hostname();
our %Opt = (makepem => 1,
            hostname => $sys_hostname,
            pause_key_file => "/etc/csync2/pause_perl_org.key",
            check_inetd => 1,
           );
GetOptions(\%Opt,
           "hostname=s",
           "makepem!",
           "check_inetd!",
          );
warn "Configuring csync2 to act as a slave of pause.perl.org:

hostname:    $Opt{hostname}
makepem:     $Opt{makepem}
check_inetd: $Opt{check_inetd}
";

if ($Opt{makepem}) {
  my $pemfile = "/etc/csync2_ssl_cert.pem";
  if (-f $pemfile) {
    die "pemfile[$pemfile] exists, won't overwrite. If this is ok, call me with --nomakepem";
  } else {
    my $keyfile = "/etc/csync2_ssl_key.pem";
    my $csrfile = "/etc/csync2_ssl_cert.csr";
    unless (-f $keyfile) {
      0==system "openssl genrsa -out $keyfile 2048" or die;
    }
    unless (-f $csrfile) {
      0==system "yes ''|openssl req -new -key $keyfile -out $csrfile" or die;
    }
    my $days = int((2**31-1-time)/86400);
    0==system "openssl x509 -req -days $days -in $csrfile -signkey $keyfile -out $pemfile" or die;
  }
}

unless (-f $Opt{pause_key_file}) {
  mkpath dirname $Opt{pause_key_file};
  open my $fh, ">", $Opt{pause_key_file} or die;
  print $fh "perl" x 8, "\n";
}

### If PAUSE would run a csync2 process, this would do:
# % csync2 -v -T /home/ftp/pub/PAUSE/authors/02STAMP -N $HOSTNAME


my $db = "/var/lib/csync2/$Opt{hostname}.db";
unless (-f $db) {
  die "Missing file '$db', cannot continue";
}

my $dbh = DBI->connect("dbi:SQLite2:dbname=$db","","") or die;
$dbh->do(q{delete from x509_cert where peername="pause.perl.org"})
    or die "Could not alter the database '$db': $DBI::errstr";
my $certdata = "30820306308201EE020900B5184B1CECD288E3300D06092A864886".
"F70D01010405003045310B3009060355040613024155311330110603550408130A536".
"F6D652D53746174653121301F060355040A1318496E7465726E657420576964676974".
"7320507479204C7464301E170D3036303432303033343633385A170D3338303131383".
"033343633385A3045310B3009060355040613024155311330110603550408130A536F".
"6D652D53746174653121301F060355040A1318496E7465726E6574205769646769747".
"320507479204C746430820122300D06092A864886F70D01010105000382010F003082".
"010A0282010100CA202ABA0F2E7091F9A22439551E7DA910BF085B8F8055C2761768E".
"00445E0A582A2CBDFD130F6F1BCF69AC914063CC0B263E47644C7BCBF1E4644F9C2E4".
"8DABDB5A18A6777561C126FD5B4358383B71492C39BE87EE3E87E8889C9ECFA61DA23".
"A12984C9984EBA63F6BC1A5F222CCE833A8201F6C12FD918A4DEA77D47D3FB2626B97".
"0909D7C4188974B3F03B505F52314DA88FC79FDC39C449BA7ADC7AA86B8ECA64801A2".
"6B0E750949D9A241DA3DB410E62E0B268A78BA27642F3CCB8C0C9392E66D722D1CBB4".
"C835433A5D83B7095397CE05486ED6FB84726F755FDC9D90FB7E242AD3D461A3F439E".
"0CBEC6DE209A70771BB3F539396F0B4011B4CF876690203010001300D06092A864886".
"F70D010104050003820101005184C3C1FEE523418EB1750F8B114746F3D5511C47ADB".
"4A9C765EBA9A615719C1BC681242419660C7CD02769E79F9FE932B48B03217055C4A0".
"B93BD2EE3B80D5ABB597F70A9110A3C564F88A3798FFABA53B94450BE0C7A2D07B421".
"F693C6A056CB0C1FA8E6498C9643A3CEF86349E921F711B2CF0E22E646DAD0010D1CA".
"429CC217350C71F5CCF82CAE20E44114B359620A5577AA05FCD444A1426162E052CB9".
"031E70177658748967D81F31821DA5CD27E53A214CC1B87F74628B95C632D209C2B44".
"446FA52294DCD8F886D999AD00B5D1321437E12061E2F6B23F94155E5797D7A64368A".
"ECCADB1D217B5F06AC418671651F0FB5F248C6823DAA2DE8B6E11";

$dbh->
    do(qq{insert into x509_cert (peername, certdata) values ("pause.perl.org","$certdata")})
    or die "Could not alter the database '$db': $DBI::errstr";


unless ($Opt{check_inetd}) {
  open my $fh, "/etc/inetd.conf" or die;
  local $/ = "\n";
  my $failmess = "Please correct or if this is indeed correct, rerun me with --nocheck_inetd";
  my $csync2_line_found;
  while (<$fh>) {
    chomp;
    next unless /^csync2/;
    $csync2_line_found++;
    my(@inet_args) = split " ", $_;
    die "csync2 line in inetd.conf too short" unless $#inet_args>6;
    unless ($Opt{hostname} eq $sys_hostname) {
      my $minus_N_ok;
      for my $i (6..$#inet_args) {
        if ($inet_args[$i] eq "-N") {
          if ($inet_args[$i+1] eq $Opt{hostname}) {
            $minus_N_ok++;
          }
        }
      }
      unless ($minus_N_ok) {
        die "Your csync2 line in your inetd has not the expected argument '-N $Opt{hostname}'.
$failmess";
      }
    }
  }
  unless ($csync2_line_found) {
    die "Missing csync2 line in your inetd.conf\n$failmess";
  }
}

{
  my $pause_stanza = qq{
group pause_perl_org {
  host pause.perl.org;
  host ($Opt{hostname});
  key $Opt{pause_key_file};
  include /home/ftp/pub/PAUSE/authors;
  include /home/ftp/pub/PAUSE/modules;
  include /home/ftp/pub/PAUSE/scripts;
  auto left;
}
};
  my $write;
  my $outfh;
  my $csync2file = "/etc/csync2.cfg";
  if (open my $fh, $csync2file) {
    my $csync2 = do { local $/; <$fh> };
    if ($csync2 =~ m|
                     \bgroup\b\s*                       # group
                     \w+\s*                             # groupname
                     \{\s*
                     host\s*pause\.perl\.org\s*;\s*     # pause.perl.org
                     host\s*\(\Q$Opt{hostname}\E\);\s*  # own host
                     key\s+\Q$Opt{pause_key_file}\E;\s* # keyfile
                     include \s+ /home/ftp/pub/PAUSE/authors;\s* #
                     include \s+ /home/ftp/pub/PAUSE/modules;\s* #
                     include \s+ /home/ftp/pub/PAUSE/scripts;\s* #
                     auto \s+ left;\s*                           #
                     \}
                    |sx) {
      warn "$csync2file looks good";
    } else {
      open $outfh, ">>", $csync2file or die;
      warn "Appending the pause stanza to $csync2file";
      $write++;
    }
  } else {
    open $outfh, ">", $csync2file or die;
    warn "Writing the pause stanza to $csync2file";
    $write++;
  }
  if ($write) {
    print $outfh $pause_stanza;
  }
}

die "Todo: /home/ftp/pub/PAUSE/* checken; search csync2 in the path; ";

warn "Your csync2 slave is ready to go now. Please tell the PAUSE admin to add your host '$Opt{hostname}' to the csync2 config";

### How to call csync2 on the master (PAUSE does that itself):
# ONCE:
# % ~k/PAUSE/cron/csync-wrapper.pl -tuxi $Opt{hostname} &
# REGULARLY:
# % csync2 -x -v -G pause_perl_org -N pause.perl.org

