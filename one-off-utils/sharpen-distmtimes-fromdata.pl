#!/usr/bin/perl

=pod

Better name would hve been: reindex-from-lst or some such.

Remove everything from distmtimes that prevents mldistwatch from indexing.

Used twice to fix #16293 on rt.cpan.org

=cut

use strict;
use warnings;

use lib "lib", "privatelib";
use PAUSE;

my $dbh = PAUSE::dbh;
my $sth = $dbh->prepare("delete from distmtimes where dist=?");
$| = 1;
while (<DATA>){
  chomp;
  my $rows = $sth->execute($_);
  print $rows;
  sleep 360;
}
print "\n";

__END__
D/DM/DMUEY/Acme-Scripticide-v0.0.4.tar.gz
D/DM/DMUEY/Acme-ScriptoPhrenic-v0.0.2.tar.gz
D/DM/DMUEY/AltaVista-BabelFish-v42.0.1.tar.gz
D/DM/DMUEY/Unix-PID-v0.0.2.tar.gz
D/DO/DOUGW/LISP-0.01.tar.gz
F/FK/FKUO/MCrypt-0.92.tar.gz
F/FK/FKUO/Mhash-0.90.tar.gz
G/GA/GAAS/UDDI-0.03.tar.gz
G/GE/GENE/URI-Collection-0.08.tar.gz
J/JA/JASONK/Data-Faker-0.07.tar.gz
J/JE/JETTERO/MySQL-GUI-0.33.tar.gz
J/JG/JGLICK/ModsPragma-0.004.tar.gz
J/JG/JGLICK/Sys-Pushd-0.001.tar.gz
J/JG/JGLICK/Test-Helper-0.002.tar.gz
J/JO/JONAS/RDF-Service-0.04.tar.gz
K/KR/KRAEHE/CGI-pWiki-0.15.tar.gz
L/LM/LMEYER/Class-Std-Storable-v0.0.1.tar.gz
L/LU/LUISMUNOZ/Authen-PIN-1.10.tar.gz
L/LU/LUISMUNOZ/Barcode-Cuecat-1.20.tar.gz
L/LU/LUISMUNOZ/Number-Encode-1.00.tar.gz
M/MA/MAIRE/Chess-Pgn-0.03.tar.gz
M/MA/MARCEL/Attribute-TieClasses-0.01.tar.gz
M/MA/MARCEL/DBIx-Renderer-0.01.tar.gz
M/MA/MARCEL/GraphViz-ISA-0.01.tar.gz
M/MC/MCMAHON/WWW-Mechanize-Plugin-Cache-0.02.tar.gz
M/ME/METZZO/Variable-Strongly-Typed-v1.1.0.tar.gz
M/MG/MGILFIX/Notify-0.0.1.tar.gz
M/ML/MLEHMANN/Gimp-1.211.tar.gz
M/MS/MSPENCER/ProLite-0.01.tar.gz
N/NM/NMCFARL/Net-Growl-0.99.tar.gz
P/PD/PDCAWLEY/Interface-Polymorphism-0.2.tar.gz
P/PT/PTULLY/FedEx-0.10.tar.gz
S/SA/SAMTREGAR/Tie-IntegerArray-0.01.tar.gz
S/SP/SPURKIS/Pangloss-0.06.tar.gz
S/SP/SPURKIS/accessors-0.02.tar.gz
S/ST/STEVEGT/Mail-TieFolder-0.03.tar.gz
S/ST/STEVEGT/Mail-TieFolder-mh-0.04.tar.gz
T/TO/TODD/SQL-Schema-0.31.tar.gz
W/WM/WMCKEE/Petal-Utils-0.06.tar.gz
