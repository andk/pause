

=pod

steffen took the herculean task on to talk to the owners of >700
namespaces whose modules he could not find.

From the responses he collected 116 confirmed deletes and from other
investigations he collected 48.

We throw them all together in this script.

=cut


use strict;
use warnings;


my @confirmed = split /\n/, <<EOL;
Acme::l33t YANICK
AI::NeuralNet JBRYAN
Algorithm::Munkre ANAGHAKK
Alien::Dojo DOMQ
Apache::CallHandler GKNOPS
Apache::Servlet IKLUFT
Archive::Parity FGLOCK
Array::Reform TBONE
Async::Process DDUMONT
Authen::OTP ZEFRAM
Bleach DCONWAY
Bundle::Net::SXIP::Homesite KGRENNAN
Business::Payroll::AU::PAYG PJF
CGI::DBTables FRIEDO
CGI::FormManager ANDREWF
CGI::MxWidget RAM
Chatbot::RiveScript KIRSLE
Class::Holon GSLONDON
Class::PublicInternal MIKO
ClearCase BRADAPP
CMS::Mediawiki RETOH
ControlX10::CM10 BBIRTH
Crypt::Camellia JCDUQUE
Data::FormValidator::Upload MARKSTOS
Data::Stash HRANICKY
Db::dmObject JGARRISON
DCE::RPC PHENSON
Devel::Coverage RJRAY
Devel::DebugAPI JHA
Device::PLC COSIMO
Email::Send::SMTP::Auth MTHURN
FileSys::Tree COG
Games::Go::GoPair REID
Geo:Gpx ANDYA
Getopt::Long::File MOINEFOU
Google::Spreadsheet LPETERS
Graphics::Turtle NEERI
Hardware::Simulator GSLONDON
HTML::BarChart TAG
HTTPD::Access LDS
HTTP::Test RAM
IO::Filter RWMJ
Lexical::Typeglob JJORE
Lingua::EN::Cardinal HIGHTOWE
Lingua::EN::Ordinal HIGHTOWE
Lingua::FeatureSet KAHN
Log::Check LPETERS
Math::Interpolate MATKIN
Math::Nocarry BDFOY
Math::Sparse::Matrix TPEDERSE
Math::Sparse::Vector TPEDERSE
Module::MakeDist RSAVAGE
Net::DNS::Zone OLAF
Net::Mac::Vendor BDFOY
Net::MsgLink RAM
Neural LUKKA
NexTrieve::Collection ELIZABETH
NexTrieve::Collection::Index ELIZABETH
NexTrieve::Daemon ELIZABETH
NexTrieve::DBI ELIZABETH
NexTrieve::Docseq ELIZABETH
NexTrieve::Document ELIZABETH
NexTrieve ELIZABETH
NexTrieve::Hitlist ELIZABETH
NexTrieve::Hitlist::Hit ELIZABETH
NexTrieve::HTML ELIZABETH
NexTrieve::Index ELIZABETH
NexTrieve::Mbox ELIZABETH
NexTrieve::Message ELIZABETH
NexTrieve::MIME ELIZABETH
NexTrieve::Overview ELIZABETH
NexTrieve::PDF ELIZABETH
NexTrieve::Query ELIZABETH
NexTrieve::Querylog ELIZABETH
NexTrieve::Replay ELIZABETH
NexTrieve::Resource ELIZABETH
NexTrieve::RFC822 ELIZABETH
NexTrieve::Search ELIZABETH
NexTrieve::Targz ELIZABETH
NexTrieve::UTF8 ELIZABETH
Nexus RDO
P4::Client SMEE
Parse::Debian::Release HARDCODE
Parse::Debian::Sources HARDCODE
Parse::Debian::SourcesList HARDCODE
POE::Session::GladeXML MARTIJN
Poetry::Vogon AMS
RPM::Headers RJRAY
RTF::Generator RRWO
Search::Kinosearch CREAMYG
Smirch JNAGRA
Snippets BACHMANN
Sparky JLHOLT
Spool::Queue RAM
Sybase::Async WORENKD
Text::Bib ERYQ
Text::Invert NNEUL
Text::Template::Queue SILI
Tie::Mem PMQS
Tie::WarnGlobal STEPHEN
Time::JulianDateTime AQUACADE
Time::Space::Adaptive DPRICE
Unicode::Normal MHOSKEN
Unix::UserAdmin JZAWODNY
VCS::RCE RJRAY
VCS::RCS RJRAY
VDBM RAM
Widget::FixedWidthFont::Input CORLISS
Win32::COM JDB
Win32::GUID ANDY
WWW::Search::Excite MTHURN
WWW::Search::HotBot MTHURN
WWW::Search::Lycos MTHURN
WWW::Search::Magellan MTHURN
X11::Fvwm RJRAY
XML::Validator::RelaxNG PCIMPRICH
EOL

my @handchecked = grep { $_ &&! /^-/ &&! /\./} split /\n/, <<EOL;
- Typoes and the like:
WWW:Blogger ERMEYERS (misspelt, but package on backpan)
Persistence::Object VIPUL  (Uploaded Object::Persistence)
Tern::Size::Heuristic YUMPY  (typo)

- No implementation on CPAN. Also, this is the author's only registered
module and the author never uploaded any files.
Asterisk::IVR::Dido QUINN
XML::Pastor AULUSOY
YATT HKOBA

- No implementation on CPAN:
ADT ABERGMAN
ADT::Queue::Priority ABERGMAN
Apache::AuthenGSS DOUGM
Apache::AuthzDCE DOUGM
Apache::Byterun DOUGM
Apache::DCELogin DOUGM
Apache::DynaRPC DOUGM
Apache::ProxyCache DOUGM
Apache::RoleAuthz DOUGM
Apache::WatchDog DOUGM
AsciiDB::Parse MICB
BarCode::UPC JONO
Carp::CheckArgs GARROW
Convert::Base VIPUL
Crypt::ElGamal VIPUL
Exporter::Import GARROW
FrameMaker::Control PEASE
FrameMaker::FDK PEASE
FrameMaker::MIF PEASE
FrameMaker PEASE
Getopt::Help IANPX
Image::Colorimetry JONO
IO::STREAMS PETDANCE
Mail::VersionTracker FHOXH
Math::Fourier AQUMSIEH
Math::Integral AQUMSIEH
Math::LinearProg JONO
Net::IMIP SRL
Net::ITIP SRL
POE::Component::IRC::Onjoin FHOXH
POE::Component::IRC::SearchEngine FHOXH
Proxy MICB
Proxy::Tk MICB
Psion::Db IANPX
Reefknot::Client SRL
Reefknot::Server SRL
SOOP GARROW
Sys::Sysconf PETDANCE
Term::Size::Heuristic YUMPY
Text::Stem IANPX
WWW::WordPress SENGER
Xmms::Plugin DOUGM
EOL

die sprintf "assertion failure: \@confirmed not == 116: %d", scalar @confirmed, unless @confirmed == 116;
die sprintf "assertion failure: \@handchecked not == 48: %d", scalar @handchecked, unless @handchecked == 48;

my @dele;
for my $e (@confirmed,@handchecked) {
  $e =~ s/\s*\(.*//;
  my(@m) = split /\s/, $e;
  die "assertion failure: 'e' not consisting of m/e" if @m != 2;
  push @dele, $m[0];
}

die sprintf "assertion failure: \@dele not == 116+48: %d", scalar @dele, unless @dele == 116+48;


$|=1;

if (-f "$ENV{HOME}/dproj/PAUSE/00-before-SVN/modulelist/moddump.current") {
  for my $dele (@dele) {
    print ".";
    my @result = `grep "'$dele'" ~/dproj/PAUSE/00-before-SVN/modulelist/moddump.current`;
    
    for my $table (qw(mods perms primeur)) {
      my @subresult = grep /INSERT INTO .$table. /, @result;
      my $max = 1;
      if ($dele =~ /^(Apache::DCELogin|WWW::Search::.*)$/) {
        $max = 2;
      }
      if (@subresult > $max) {
        local $" = "\n";
        warn @subresult < 20 ? "@subresult" : sprintf "%s and %d more", $subresult[0], @subresult-1;
        die "not exactly one record for '$dele'";
      }
    }
  }
}
print "\n";

use lib "/home/k/PAUSE/lib", "/home/k/dproj/PAUSE/SVN/lib";
use PAUSE;
use DBI;

my $db = DBI->connect(
                      $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
                      $PAUSE::Config->{MOD_DATA_SOURCE_USER},
                      $PAUSE::Config->{MOD_DATA_SOURCE_PW},
                      {RaiseError => 0}
                     );

my $sth1 = $db->prepare("SELECT * FROM mods WHERE modid=?");
my $sth2 = $db->prepare("SELECT * FROM perms WHERE package=?");
my $sth3 = $db->prepare("SELECT * FROM primeur WHERE package=?");
for my $dele (@dele) {
  $sth3->execute($dele);
  $sth2->execute($dele);
  $sth1->execute($dele);
  die "assertion failure: $dele not in mods" unless $sth1->rows == 1;
}


my $sth4 = $db->prepare("DELETE FROM mods WHERE modid=?");
my $sth5 = $db->prepare("DELETE FROM perms WHERE package=?");
my $sth6 = $db->prepare("DELETE FROM primeur WHERE package=?");
for my $dele (@dele) {
  my $cnt = $sth6->execute($dele);
  print "p$cnt";
  $cnt = $sth5->execute($dele);
  print ".p$cnt";
  $cnt = $sth4->execute($dele);
  print ".m$cnt|";
  die "die assertion failure: $dele/$cnt" unless $cnt==1;
  print "'$dele' done\n";
  sleep 2;
}

