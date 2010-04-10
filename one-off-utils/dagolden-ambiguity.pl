#!/usr/bin/perl

use strict;
use File::Basename qw(dirname);
use File::Path qw(mkpath);
use Digest::SHA qw(sha1_hex);

my($distv,%S,@unequal,@equal,@unequal2);
$|++;
while (<DATA>) {
    chomp;
    if (/^(\S+)/) {
        $distv = $1;
    } elsif (/^\s+(\S+)/) {
        my $adistv = $1;
        next if $adistv =~ /^#/;
        my($author,$distv) = $adistv =~ m|(^[^/]+)/(\S+)|;
        my $audir = substr($author,0,1) . "/" . substr($author,0,2) . "/" . $author;
        my $abs = "/home/ftp/pub/PAUSE/authors/id/$audir/" . $distv;
        # print -f $abs ? "+" : ".";
        unless (-f $abs) {
            require LWP::UserAgent;
            my $ua = LWP::UserAgent->new;
            mkpath dirname $abs;
            print "Fetching $abs";
            my $url = "http://backpan.cpan.org/authors/id/$audir/" . $distv;
            $ua->mirror($url,$abs) or die;
            print "...DONE";
            sleep 1;
        }
        my $slurp = do { open my $fh, $abs or die; local $/; <$fh> };
        my $sha1 = sha1_hex $slurp;
        my $xstat = $S{$distv} ||= {};
        push @{$xstat->{abs}}, $abs;
        if ($xstat->{firstsha1}) {
            if ($xstat->{firstsha1} eq $sha1) {
                #print "=";
                push @equal, $distv;
            } else {
                #print "!";
                push @unequal, $distv;
                my $n = 1 + @unequal2;
                push @unequal2, "$n. $distv ($xstat->{firstauthor} vs. $author)";
            }
        } else {
            $xstat->{firstsha1} = $sha1;
            $xstat->{firstauthor} = $author;
        }
    }
}
print "\n";
for my $distv (@unequal2) {
    my $xstat = $S{$distv};
    for my $abs (@{$xstat->{abs}}) {
        system "ls -l $abs";
    }
    print $distv, "\n";
    my @authors = $distv =~ /\((\w+) vs. (\w+)\)/;
    my $module = $distv;
    $module =~ s/^\d+\.\s+//;
    $module =~ s/-\d.*//;
    $module =~ s/-/::/g;
    open my $fh, "-|", "grep ^$module, /home/ftp/pub/PAUSE/modules/06perms.txt" or die;
    my %authorized;
    while (<$fh>) {
        # print;
        my($d,$a,$t) = split /,/, $_;
        $authorized{$a} = 1;
    }
    my @authorized = grep { $authorized{$_} } @authors;
    if (@authorized == 0) {
        print "None of them authorized\n";
    } elsif (@authorized == 2) {
        print "Both of them authorized\n";
    } else {
        print "Only @authorized authorized\n";
    }
}
#print join "\n", @unequal2;
print "\n";


__END__
Attribute-Memoize-0.01
  DANKOGAI/Attribute-Memoize-0.01.tar.gz
  MARCEL/Attribute-Memoize-0.01.tar.gz
B-Generate-1.12_03
  JCROMIE/B-Generate-1.12_03.tar.gz
  JJORE/B-Generate-1.12_03.tar.gz
Bundle-Cobalt-0.01
  HARASTY/Bundle-Cobalt-0.01.tar.gz
  JPEACOCK/Bundle-Cobalt-0.01.tar.gz
CDDB-0.9
  FONKIE/CDDB-0.9.tar.gz
  KRAEHE/CDDB-0.9.tar.gz
Catalyst-Plugin-Session-Store-File-0.07
  ESSKAR/Catalyst-Plugin-Session-Store-File-0.07.tar.gz
  KARMAN/Catalyst-Plugin-Session-Store-File-0.07.tar.gz
Catalyst-Plugin-Static-0.05
  MRAMBERG/Catalyst-Plugin-Static-0.05.tar.gz
  SRI/Catalyst-Plugin-Static-0.05.tar.gz
Catalyst-Plugin-Static-Simple-0.14
  AGRUNDMA/Catalyst-Plugin-Static-Simple-0.14.tar.gz
  MRAMBERG/Catalyst-Plugin-Static-Simple-0.14.tar.gz
Crypt-SSLeay-0.51
  # CHAMAS/Crypt-SSLeay-0.51.tar.gz
  # TAKESAKO/Crypt-SSLeay-0.51.tar.gz
Curses-UI-0.72
  MARCUS/Curses-UI-0.72.tar.gz
  MMAKAAY/Curses-UI-0.72.tar.gz
Curses-UI-0.73
  MARCUS/Curses-UI-0.73.tar.gz
  MMAKAAY/Curses-UI-0.73.tar.gz
DateManip-5.20
  PHOENIX/DateManip-5.20.tar.gz
  SBECK/DateManip-5.20.tar.gz
Finance-Bank-HSBC-1.04
  BISSCUITT/Finance-Bank-HSBC-1.04.tar.gz
  MWILSON/Finance-Bank-HSBC-1.04.tar.gz
Finance-Bank-HSBC-1.05
  BISSCUITT/Finance-Bank-HSBC-1.05.tar.gz
  MWILSON/Finance-Bank-HSBC-1.05.tar.gz
Locale-Object-0.73
  EMARTIN/Locale-Object-0.73.tar.gz
  FOTANGO/Locale-Object-0.73.tar.gz
MARC-0.81
  BBIRTH/MARC-0.81.tar.gz
  ESUMMERS/MARC-0.81.tar.gz
MARC-1.13
  ESUMMERS/MARC-1.13.tar.gz
  PETDANCE/MARC-1.13.tar.gz
Mail-Thread-2.41
  RCLAMP/Mail-Thread-2.41.tar.gz
  SIMON/Mail-Thread-2.41.tar.gz
Math-MatrixReal-1.1
  # ANDK/Math-MatrixReal-1.1.tar.gz
  # STBEY/Math-MatrixReal-1.1.tar.gz
Maypole-Authentication-Abstract-0.6
  BOBTFISH/Maypole-Authentication-Abstract-0.6.tar.gz
  SRI/Maypole-Authentication-Abstract-0.6.tar.gz
Maypole-Config-YAML-0.1
  BOBTFISH/Maypole-Config-YAML-0.1.tar.gz
  SRI/Maypole-Config-YAML-0.1.tar.gz
Maypole-Loader-0.1
  BOBTFISH/Maypole-Loader-0.1.tar.gz
  SRI/Maypole-Loader-0.1.tar.gz
Maypole-Plugin-Authentication-Abstract-0.10
  BOBTFISH/Maypole-Plugin-Authentication-Abstract-0.10.tar.gz
  SRI/Maypole-Plugin-Authentication-Abstract-0.10.tar.gz
Maypole-Plugin-Component-0.05
  BOBTFISH/Maypole-Plugin-Component-0.05.tar.gz
  SRI/Maypole-Plugin-Component-0.05.tar.gz
Maypole-Plugin-Config-YAML-0.04
  BOBTFISH/Maypole-Plugin-Config-YAML-0.04.tar.gz
  SRI/Maypole-Plugin-Config-YAML-0.04.tar.gz
Maypole-Plugin-Exception-0.03
  BOBTFISH/Maypole-Plugin-Exception-0.03.tar.gz
  SRI/Maypole-Plugin-Exception-0.03.tar.gz
Maypole-Plugin-I18N-0.02
  BOBTFISH/Maypole-Plugin-I18N-0.02.tar.gz
  SRI/Maypole-Plugin-I18N-0.02.tar.gz
Maypole-Plugin-Loader-0.03
  BOBTFISH/Maypole-Plugin-Loader-0.03.tar.gz
  SRI/Maypole-Plugin-Loader-0.03.tar.gz
Maypole-Plugin-Relationship-0.03
  BOBTFISH/Maypole-Plugin-Relationship-0.03.tar.gz
  SRI/Maypole-Plugin-Relationship-0.03.tar.gz
Maypole-Plugin-Transaction-0.02
  BOBTFISH/Maypole-Plugin-Transaction-0.02.tar.gz
  SRI/Maypole-Plugin-Transaction-0.02.tar.gz
Maypole-Plugin-Untaint-0.04
  BOBTFISH/Maypole-Plugin-Untaint-0.04.tar.gz
  SRI/Maypole-Plugin-Untaint-0.04.tar.gz
Net-DNS-0.02
  # ANDK/Net-DNS-0.02.tar.gz
  # MFUHR/Net-DNS-0.02.tar.gz
Net-SSH2-0.07
  AWA/AWA/Net-SSH2-0.07.tar.gz
  DBROBINS/Net-SSH2-0.07.tar.gz
NetPacket-0.04
  ATRAK/NetPacket-0.04.tar.gz
  CGANESAN/NetPacket-0.04.tar.gz
PDL-2.3.2
  CSOE/PDL-2.3.2.tar.gz
  KGB/PDL-2.3.2.tar.gz
PNGgraph-1.11
  DMOW/PNGgraph-1.11.tar.gz
  SBONDS/PNGgraph-1.11.tar.gz
POE-Session-Attributes-0.01
  CFEDDE/POE-Session-Attributes-0.01.tar.gz
  JSN/POE-Session-Attributes-0.01.tar.gz
Plucene-1.19
  SIMON/Plucene-1.19.tar.gz
  STRYTOAST/Plucene-1.19.tar.gz
RT-Extension-MergeUsers-0.02
  JESSE/RT-Extension-MergeUsers-0.02.tar.gz
  KEVINR/RT-Extension-MergeUsers-0.02.tar.gz
SNMP-1.6
  GSM/SNMP-1.6.tar.gz
  WMARQ/SNMP-1.6.tar.gz
SXIP-Membersite-1.0.0
  # KGRENNAN/SXIP-Membersite-1.0.0.tar.gz
  # TOKUHIROM/SXIP-Membersite-1.0.0.tar.gz
Scalar-Defer-0.13
  AUDREYT/Scalar-Defer-0.13.tar.gz
  NUFFIN/Scalar-Defer-0.13.tar.gz
Term-Prompt-0.02
  ALLENS/Term-Prompt-0.02.tar.gz
  DAZJORZ/Term-Prompt-0.02.tar.gz
Term-Prompt-0.05
  ALLENS/Term-Prompt-0.05.tar.gz
  DAZJORZ/Term-Prompt-0.05.tar.gz
Test-Warn-0.07
  BIGJ/Test-Warn-0.07.tar.gz
  MPRESSLY/Test-Warn-0.07.tar.gz
Time-0.01
  JPRIT/Time-0.01.tar.gz
  PGOLLUCCI/Time-0.01.tar.gz
Tk-Wizard-Bases-1.07
  LGODDARD/Tk-Wizard-Bases-1.07.tar.gz
  MTHURN/Tk-Wizard-Bases-1.07.tar.gz
UUID-0.03
  CFABER/UUID-0.03.tar.gz
  LZAP/UUID-0.03.tar.gz
Win32-EventLog-Carp-1.21
  IKEBE/Win32-EventLog-Carp-1.21.tar.gz
  RRWO/Win32-EventLog-Carp-1.21.tar.gz
YAML-0.39
  INGY/YAML-0.39.tar.gz
  KING/YAML-0.39.tar.gz
finance-yahooquote_0.19
  DJPADZ/finance-yahooquote_0.19.tar.gz
  EDD/finance-yahooquote_0.19.tar.gz
libapreq-1.33
  GEOFF/libapreq-1.33.tar.gz
  STAS/libapreq-1.33.tar.gz
pg95perl5-1.2.0
  MERGL/pg95perl5-1.2.0.tar.gz
  YVESP/pg95perl5-1.2.0.tar.gz
