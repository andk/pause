#!/usr/bin/perl

# use 5.010;
use strict;
use warnings;

=head1 NAME



=head1 SYNOPSIS



=head1 OPTIONS

=over 8

=cut

my @opt = <<'=back' =~ /B<--(\S+)>/g;

=item B<--dry-run|n!>

Run the from-mods-to-primeur.pl with the --dry-run option.

=item B<--help|h!>

This help

=back

=head1 DESCRIPTION

As in the previous batchfiles, converting-m-to-f-*.pl, Neil
Bowers sent me the data and I wrapped them into the script.

=cut

use FindBin;
use lib "$FindBin::Bin/../lib";
BEGIN {
    push @INC, qw(       );
}

use Dumpvalue;
use File::Basename qw(dirname);
use File::Path qw(mkpath);
use File::Spec;
use File::Temp;
use Getopt::Long;
use Pod::Usage;
use Hash::Util qw(lock_keys);

our %Opt;
lock_keys %Opt, map { /([^=|!]+)/ } @opt;
GetOptions(\%Opt,
           @opt,
          ) or pod2usage(1);
if ($Opt{help}) {
    pod2usage(0);
}
$Opt{"dry-run"} //= 0;
my @dry_run;
push @dry_run, "--dry-run" if $Opt{"dry-run"};
use Time::HiRes qw(sleep);

my $i = 0;
while (<DATA>) {
    chomp;
    my $csv = $_;
    my($m,$a,$type) = split /,/, $csv;
    die "illegal type" unless $type eq "m";
    my $t = scalar localtime;
    $i++;
    warn sprintf "(%d) %s: %s\n", $i, $t, $m;
    0 == system "/opt/perl/current/bin/perl", "-Iprivatelib", "-Ilib", "bin/from-mods-to-primeur.pl", @dry_run, $m or die "Alert: $t: Problem while running from-mods-to-primeur for '$m'";
    sleep 0.08;
}

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:

__END__
Find::File::Object,NANARDON,m
HTML::Mason,JSWARTZ,m
Apache::ExtUtils,APML,m
DbFramework::Key,IMACAT,m
Apache::httpd_conf,APML,m
DBI::Format,TLOWERY,m
DBD::Multiplex,TKISHEL,m
Net::ICal,SRL,m
PDF::Core,ANTRO,m
Locale::gettext,PVANDRY,m
Tk::SplitFrame,DKWILSON,m
Search::FreeText,SARGIE,m
Tk::Axis,TKML,m
SGML::SPGrove,KMACLEOD,m
WWW::GoodData,MAIO,m
MooseX::Method,BERLE,m
eBay::API,EBAY,m
ObjStore,JPRIT,m
Net::IMAP::Simple,JPAF,m
Text::MicroMason,FERRENCY,m
Catalyst::Plugin::Params::Nested,NUFFIN,m
Java::Javap,PHILCROW,m
Catalyst::Plugin::Authentication::Store::DBIx::Class,BOBTFISH,m
Apache::Debug,APML,m
WebService::UWO::Directory,FREQUENCY,m
Regexp,GBARR,m
DbFramework::Table,IMACAT,m
PDL::LinearAlgebra,ELLIPSE,m
Tk::PathEntry,SREZIC,m
Catalyst::Plugin::UploadProgress,AGRUNDMA,m
HTML::HeadParser,LWWWP,m
Getopt::Long::Descriptive,HDP,m
SGMLS,INGOMACH,m
SDL::Game,KTHAKORE,m
PDF::Labels,OWEN,m
Event::tcp,JPRIT,m
SVG::Manual,RONAN,m
HTML::Template,SAMTREGAR,m
Apache::AuthenIMAP,MICB,m
Qt4,JAWNSY,m
Jifty,JESSE,m
Test::Suite,EXODIST,m
Tk::JPEG,TKML,m
Audio::ScratchLive,CAPOEIRAB,m
Algorithm::QuineMcCluskey,KULP,m
URI::Attr,LWWWP,m
CGI::BasePlus,CGIP,m
Win32::ASP,WNODOM,m
Tk::Pane,TKML,m
Tamino,YURAN,m
Business::US::USPS::WebTools,ADOPTME,m
Net::Server,RHANDOM,m
Tk::Columns,DKWILSON,m
Convert::CharMap,AUTRIJUS,m
Apache::AuthzAge,APML,m
Net::Server::Mail::ESMTP::XFORWARD,GUIMARD,m
ExtUtils::Embed,DOUGM,m
Inline::Python,NEILW,m
WebNano,ZBY,m
Date::Parse,GBARR,m
Bio,SEB,m
Apache::Connection,APML,m
Net::DummyInetd,GBARR,m
Attribute::Abstract,MARCEL,m
OurNet,AUTRIJUS,m
Archive::Tar,KANE,m
POE::Component::Client::Whois::Smart,GRAYKOT,m
Net::Subnets,SRI,m
Apache::FakeRequest,APML,m
Catalyst::Plugin::Session,NUFFIN,m
LWP::Conn,LWWWP,m
Tk::TabFrame,DKWILSON,m
OS2::REXX,ILYAZ,m
Net::SMTP,GBARR,m
DB_File,PMQS,m
Tk::TableEdit,DKWILSON,m
Slash::OurNet,AUTRIJUS,m
Apache::Timeit,APML,m
Image::Grab,GENEHACK,m
Date::Convert,MORTY,m
RTF::Group,ADOPTME,m
Search::Xapian,KILINRAX,m
Net::Whois::RIPE,LMC,m
Apache::Table,APML,m
Net::Netrc,GBARR,m
Lemonldap::NG::Common,GUIMARD,m
Tk::HTML,TKML,m
HTML::Chunks::Local,MBLYTHE,m
IO::Tty,RGIERSIG,m
Apache::SizeLimit,APML,m
Apache::ShowRequest,DOUGM,m
WWW::betfair,SILLYMOOS,m
DBD::XBase,JANPAZ,m
Win32::FUtils,JOCASA,m
WWW::SherlockSearch,AUTRIJUS,m
OS2::PrfDB,ILYAZ,m
Imager,ADDI,m
XML::Comma,KWINDLA,m
CGI::Carp,LEEJO,m
Net::ParseWhois,ABEROHAM,m
Net::SSH::Perl,DBROBINS,m
XRI,MOCONNOR,m
LSF,DXIAO,m
App::RecordStream,BERNARD,m
Lemonldap::NG::Handler,GUIMARD,m
Test::Spec,PHILIP,m
Net::Domain,GBARR,m
VCS,ADOPTME,m
SGML::Element,LSTAF,m
Lingua::ZH::TaBE,AUTRIJUS,m
Net::OAuth::Simple::AuthHeader,SIXAPART,m
OS2::ExtAttr,ILYAZ,m
XML::Xerces,JASONS,m
Algorithm::Diff,ANDREWC,m
Tk,TKML,m
CGI::Request,CGIP,m
Net::Whois::Generic,AASSAD,m
v6,FGLOCK,m
HPUX::Ioscan,CWHITE,m
PDF::API2,SSIMMS,m
NetAddr::IP,LUISMUNOZ,m
Msql,JWIED,m
Apache::URI,APML,m
SQL::Tidy,JGONZALEZ,m
GnuPG::Interface,FTOBIN,m
Net::Patricia,PLONKA,m
WWW::Discogs,LEEDO,m
Tk::Dial,TKML,m
Tk::IconCanvas,DKWILSON,m
Archive::Zip,SMPETERS,m
Net::POP3,GBARR,m
Apache::DProf,DOUGM,m
Lingua::ZH::Numbers,AUTRIJUS,m
Frontier::RPC,KMACLEOD,m
Tie::Watch,LUSOL,m
Apache::SIG,APML,m
Test::MockDBI,MLFISHER,m
HTTP::Daemon,LWWWP,m
Yahoo::Search,TIMB,m
Graphics::Simple,NEERI,m
Astro::FITS::Header,AALLAN,m
Apache::Symbol,APML,m
Apache::Mason,JSWARTZ,m
Apache::RegistryLoader,APML,m
Scalar::Util,GBARR,m
URI::Escape,LWWWP,m
Apache::ModuleConfig,APML,m
Crypt::OpenPGP,BTROTT,m
Apache::Peek,APML,m
Win32::API,ACALPINI,m
Image::Info,TELS,m
Games::AIBots,AUTRIJUS,m
ExtUtils::MakeMaker,BINGOS,m
Regexp::Genex,BOWMANBS,m
LockFile::Simple,ADOPTME,m
Apache2::Pod,KYPREOS,m
Carp::Datum,SQUIRREL,m
Win32API::File,TYEMQ,m
Apache::Status,APML,m
B,MICB,m
Net::TFTP,GSM,m
HTML::Simple,TOMC,m
Apache::Util,APML,m
Date::Language,GBARR,m
DBD::Oracle,DBIML,m
Watchdog::Service,PSHARPE,m
Apache::Session,CWEST,m
Convert::BinHex,STEPHEN,m
Apache::DB,APML,m
LWP::RobotUA,LWWWP,m
Tk::DirSelect,MJCARMAN,m
Tk::Menustrip,DKWILSON,m
Net::LDAP,PLDAP,m
Catalyst::Plugin::Authentication::Credential::HTTP,NUFFIN,m
SOAP,MKUTTER,m
Encode::compat,AUTRIJUS,m
HTML::TokeParser,LWWWP,m
PDL::NiceSlice,CSOE,m
Mail::SpamAssassin,JMASON,m
Watchdog::MysqlService,PSHARPE,m
DbFramework::Persistent,IMACAT,m
Term::ProgressBar,FLUFFY,m
Mozilla::Backup,ADOPTME,m
Apache::Sybase::DBlib,BMILLETT,m
Apache::Log,APML,m
DateTime,DROLSKY,m
String::Edit,TOMC,m
Fame,TRIAS,m
XML::Parser,MSERGEANT,m
LWP::UserAgent,LWWWP,m
CGI::Session,SHERZODR,m
Apache::Symdump,APML,m
Apache::Include,APML,m
DbFramework::ForeignKey,IMACAT,m
Apache::AxKit,MSERGEANT,m
Apache::Safe,APML,m
Test::Reporter,FHOXH,m
Inline::CPP,NEILW,m
Net::FTP,GBARR,m
Attribute::Memoize,MARCEL,m
Business::OnlinePayment,JASONK,m
RTx::Shredder,RUZ,m
LWP::Simple,LWWWP,m
Tk::ComboEntry,DKWILSON,m
Chart::Base,NINJAZ,m
Apache::GeoIP,PTERJAN,m
FCGI::ProcManager,JURACH,m
Log::Log4perl,MSCHILLI,m
Tk::PNG,TKML,m
Sys::Filesystem,NICOLAW,m
Wx,MBARBON,m
List::Util,GBARR,m
AI::Fuzzy,SABREN,m
Net::Bind,BBB,m
WWW::RobotRules,LWWWP,m
Acme::Tpyo,ALTREUS,m
Penguin,AMERZKY,m
Module::MakefilePL::Parse,ADOPTME,m
LWP,LWWWP,m
Term::ReadKey,JSTOWE,m
HTTP::DAV,PCOLLINS,m
Test::Unit,MCAST,m
Pod::Man,KJALB,m
Tcl,MICB,m
CPANPLUS,KANE,m
NetPacket::UDP,ATRAK,m
Net::NNTP,GBARR,m
PDL::Options,TJENNESS,m
HTML::Formatter,JGOFF,m
Module::Install::Skip,RUZ,m
Pod::Simplify,KJALB,m
Tk::ChildNotification,DKWILSON,m
Glib,TSCH,m
Data::Compare,FTASSIN,m
GnuPG,FRAJULAC,m
Net::Whois,DHUDES,m
Net::SSH2,DBROBINS,m
Games::Tool,KTHAKORE,m
CGI::Test,MSHILTONJ,m
Net::Amazon::EC2,JKIM,m
MIME::Latin1,DSKOLL,m
HTML::TableLayout,PERSICOM,m
Net::IRC,JEEK,m
Apache::Server,APML,m
Tk::TabbedForm,DKWILSON,m
DBD::File,HMBRAND,m
WWW::TypePad,SIXAPART,m
Gantry,TKEEFER,m
Games::Sudoku::Trainer,WITTROCK,m
Apache::Constants,APML,m
Gtk,KJALB,m
CPAN,ANDK,m
Apache::AccessLimitNum,APML,m
GD,LDS,m
Apache,DOUGM,m
SNMP,GSM,m
MARC::XML,PERL4LIB,m
Yahoo::Marketing,JLAVALLEE,m
MPEG::ID3v2Tag,CBTILDEN,m
DBIx::Class::ResultSet::RecursiveUpdate,ZBY,m
Java::Swing,PHILCROW,m
Apache::DayLimit,MPB,m
DBD::mSQL,JWIED,m
Set::Object,SAMV,m
HTML::LinkExtor,LWWWP,m
AI::NeuralNet::SOM,VOISCHEV,m
WWW::Salesforce,PHRED,m
Apache::Upload,APML,m
DbFramework::Attribute,IMACAT,m
XML::XSLT,JSTOWE,m
HTML::Chunks::Super,MBLYTHE,m
Lemonldap::NG::Portal,GUIMARD,m
Tcl::Tk,MICB,m
Apache::Leak,APML,m
VRML::Browser,LUKKA,m
Curses,GIRAFFED,m
Apache::SmallProf,DOUGM,m
Win32::GuiTest,KARASIK,m
Audio::TagLib,DONGXU,m
Weather::YR,TOREAU,m
Padre::Plugin::SpellCheck,JQUELIN,m
Algorithm::ScheduledPath,ADOPTME,m
WordNet::Similarity,SID,m
Apache::Handler,APML,m
Set::Scalar,JHI,m
NetPacket::ARP,ATRAK,m
Devel::NYTProf,TIMB,m
Test::Harness,ANDYA,m
Apache::ModuleDoc,DOUGM,m
NetPacket::IGMP,ATRAK,m
AppConfig,ABW,m
PDL::Opt::NonLinear,ELLIPSE,m
Catalyst::Plugin::Authentication::Store::DBIC,MRAMBERG,m
Devel::Peek,ILYAZ,m
Game::Base,KTHAKORE,m
SGML::Entity,KMACLEOD,m
NetPacket::IP,ATRAK,m
Apache::DumpHeaders,DOUGM,m
Finance::Quote,HAMPTON,m
PDF::Parse,ANTRO,m
Tk::TiedListbox,TKML,m
Clone::More,WAZZUTEKE,m
Apache::src,APML,m
Data::RandomPerson,PETERHI,m
Bundle::Parrot,PARROTRE,m
Apache::TicketAccess,MPB,m
Devel::dbg,LORDSPACE,m
Apache::MsqlProxy,APML,m
LWP::Protocol,LWWWP,m
Apache::Resource,APML,m
File::Copy,ASHER,m
Marpa::Guide,JKEGL,m
SQL::Interpolate,DMANURA,m
Time::Zone,GBARR,m
Apache::ProxyPassThru,RMANGI,m
CGI,LDS,m
Apache::CmdParms,APML,m
XML::Writer,JOSEPHW,m
Test::Group,DOMQ,m
DbFramework::DataType,IMACAT,m
Date::Time,TOBIX,m
Spreadsheet::WriteExcel,JMCNAMARA,m
Chart::Pie,KARLON,m
FAQ::OMatic,ABH,m
Net::FTPServer,RYOCHIN,m
Apache::Command,APML,m
Algorithm::Cluster,JNOLAN,m
NetPacket::TCP,ATRAK,m
Tripletail,MIKAGE,m
NetPacket::Ethernet,ATRAK,m
Gnome,KJALB,m
Geo::Postcodes,ARNE,m
Apache::PerlSections,APML,m
App::Config,ABW,m
Device::FTDI,ZWON,m
Goo,NIGE,m
Watchdog::HTTPService,PSHARPE,m
Mail::Freshmeat,FHOXH,m
Apache::LowerCaseGETs,PLISTER,m
PGP,PGPML,m
Tk::More,SREZIC,m
HTML::Lint,PETDANCE,m
Mail::Ezmlm,GHALSE,m
Inline::Java,PATL,m
Apache::Dispatch,GEOFF,m
DBD::Pg,DBDPG,m
Math::Trig,ZEFRAM,m
PDL::Fit::Levmar,JLAPEYRE,m
Apache::Registry,APML,m
File::Backup,GENE,m
HTML::Chunks,DBALMER,m
DbFramework::PrimaryKey,IMACAT,m
HTML::Entities,LWWWP,m
Mail::SPF,SHEVEK,m
Tie::Handle,STBEY,m
Catalyst::Plugin::Authorization::ACL,NUFFIN,m
Apache::DBI,APML,m
Tk::ProgressBar,TKML,m
Test::Cmd,KNIGHT,m
WebService::Eventful,SDDREITER,m
MP3::Tag,THOGEE,m
Locale::KeyedText,DUNCAND,m
Tk::MListbox,RCSEEGE,m
CGI::Base,CGIP,m
RT,BPS,m
Reaction,MSTROUT,m
DbFramework::Util,IMACAT,m
Tangram,JLLEROY,m
Apache::PageKit,TJMATHER,m
Net::Time,GBARR,m
Config::Any,RATAXIS,m
Class::Contract,GGOEBEL,m
Net::Cmd,GBARR,m
Ioctl,JPRIT,m
LockFile::Manager,JV,m
DBIx::HTMLView,HAKANARDO,m
Mail::ListDetector,MSTEVENS,m
Apache::StatINC,APML,m
Text::vFile,JVASILE,m
Mac::Spotlight,AHOSEY,m
DBIx::Interpolate,DMANURA,m
Win32::GUI,ACALPINI,m
CGI::MiniSvr,CGIP,m
PDF::Template,RKINYON,m
Lemonldap::NG::Manager,GUIMARD,m
RTF::Parser,SARGIE,m
PAR,AUTRIJUS,m
Apache::AuthNISPlus,VALERIE,m
Encode::HanExtra,AUTRIJUS,m
NEXT,DCONWAY,m
MIME::IO,DSKOLL,m
Acme::Playmate,ODEZWART,m
Apache::AuthCookie,MSCHOUT,m
DBIx::Cookbook,TBONE,m
Finance::Quant,SANTEX,m
DBI,TIMB,m
Apache::PerlRun,APML,m
Crypt::DES,DPARIS,m
DbFramework::DataModel,IMACAT,m
Tk::Tree,CTDEAN,m
HTTP::Cookies,LWWWP,m
Parse::ErrorString::Perl,PSHANGOV,m
Apache::SawAmpersand,APML,m
Text::Wigwam,DJOHNSTON,m
LockFile::Lock,JV,m
LWP::UA,LWWWP,m
Config::Merge,DRTECH,m
Apache::Module,APML,m
Date::Format,GBARR,m
URI::URL,LWWWP,m
Locale::Maketext::Lexicon,AUTRIJUS,m
Apache::File,APML,m
TiVo::HME,METZZO,m
Boost::Graph,DUFFEE,m
OurNet::FuzzyIndex,AUTRIJUS,m
HTML::Parser,LWWWP,m
