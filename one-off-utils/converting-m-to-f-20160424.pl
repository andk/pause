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

The difference this time is, the format has one field more:

	delete  remove this entry
	c       downgrade it to a ‘c’ (there are examples of both ‘m’ and
	        ‘f’ being downgraded)
	f       downgrade an ‘m’ to an ‘f’
	add     add this permission

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
use PAUSE;
use DBI;
my $dbh = DBI->connect(
    $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
    $PAUSE::Config->{MOD_DATA_SOURCE_USER},
    $PAUSE::Config->{MOD_DATA_SOURCE_PW},
    {RaiseError => 0}
);

my $sth1 = $dbh->prepare("update mods set mlstatus='delete' where modid=? and userid=?");
my $sth2 = $dbh->prepare("delete from primeur where package=? and userid=?");
my $sth3 = $dbh->prepare("delete from perms where package=? and userid=?");
my $sth4 = $dbh->prepare("insert into perms (package,userid) values (?,?)");
my $sth5 = $dbh->prepare("insert into primeur (package,userid) values (?,?)");

my $i = 0;
while (<DATA>) {
    chomp;
    my $csv = $_;
    next if /^\s*$/;
    next if /^#/;
    my($m,$a,$type,$action) = split /,/, $csv;
    die "illegal type" unless $type =~ /[mfc]/;
    my $t = scalar localtime;
    $i++;
    warn sprintf "(%d) %s: %s %s type=%s action=%s\n", $i, $t, $m, $a, $type, $action;
    if ($action eq "delete") {
        if ($type eq "m") {
            if ($Opt{"dry-run"}){
                warn "Would update mods 1\n";
            } else {
                warn "Setting mlstatus for modid=$m,userid=$a in mods to 'delete'";
                $sth1->execute($m,$a);
            }
        } elsif ($type eq "f") {
            if ($Opt{"dry-run"}){
                warn "Would delete first-come 1\n";
            } else {
                warn "Deleting from primeur package=$m,userid=$a";
                $sth2->execute($m,$a);
            }
        } elsif ($type eq "c") {
            if ($Opt{"dry-run"}){
                warn "Would delete comaint\n";
            } else {
                warn "Deleting from perms package=$m,userid=$a";
                $sth3->execute($m,$a);
            }
        } else {
            die "illegal";
        }
    } elsif ($action eq "c") {
        if ($type eq "m") {
            if ($Opt{"dry-run"}){
                warn "Would update mods 2 AND Would insert comaint 1\n";
            } else {
                warn "Setting mlstatus for modid=$m,userid=$a in mods to 'delete'";
                $sth1->execute($m,$a);
                warn "Inserting into perms modid=$m,userid=$a";
                $sth4->execute($m,$a);
            }
        } elsif ($type eq "f") {
            if ($Opt{"dry-run"}){
                warn "Would delete first-come 2 AND Would insert comaint 2\n";
            } else {
                warn "Deleting from primeur package=$m,userid=$a";
                $sth2->execute($m,$a);
                warn "Inserting into perms modid=$m,userid=$a";
                $sth4->execute($m,$a);
            }
        } else {
            die "illegal";
        }
    } elsif ($action eq "f") {
        if ($type eq "m") {
            if ($Opt{"dry-run"}){
                warn "Would call mods-to-primeur\n";
            } else {
                0 == system "/opt/perl/current/bin/perl", "-Iprivatelib", "-Ilib", "bin/from-mods-to-primeur.pl", @dry_run, $m or die "Alert: $t: Problem while running from-mods-to-primeur for '$m'";
            }
        } else {
            die "illegal";
        }
    } elsif ($action eq "add") {
        if ($type eq "f") {
            if ($Opt{"dry-run"}){
                warn "Would insert first-come\n";
            } else {
                warn "Inserting into primeur modid=$m,userid=$a";
                $sth5->execute($m,$a);
            }
        } else {
            die "illegal";
        }
    }
    sleep 0.08;
}

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:

__END__
# AI::nnflex,CCOLBOURN,f,delete
# AI::NNFlex,CCOLBOURN,m,f
# 
# App::GnuGet,KHAREC,f,delete
# App::Gnuget,KHAREC,m,f
# 
# Authen::NTLM,BUZZ,f,c
# Authen::NTLM,NBEBOUT,m,f
# 
# AutoReloader,SHMEM,m,c
# 
# B::C,MICB,f,c
# B::C,RURBAN,m,f
# 
# B::C,MICB,f,c
# B::C,RURBAN,m,f
# 
# Business::ISBN::Data,ESUMMERS,f,c
# Business::ISBN::Data,BDFOY,m,f
# 
# Business::OnlinePayment::CyberSource,HGDEV,f,c
# Business::OnlinePayment::Cybersource,XENO,m,f
# 
# CGI::Session::Serialize::yaml,MARKSTOS,f,c
# CGI::Session::Serialize::yaml,RSAVAGE,m,f
# 
# Catalyst::Engine::Apache,MSTROUT,f,c
# Catalyst::Engine::Apache,AGRUNDMA,m,f
# 
# Catalyst::Engine::HTTP::POE,MSTROUT,f,c
# Catalyst::Engine::HTTP::POE,AGRUNDMA,m,f
# 
# Catalyst::Plugin::I18N,MSTROUT,f,c
# Catalyst::Plugin::I18N,CHANSEN,m,f
# 
# Class::TOM,JDUNCAN,m,delete
# 
# Config::Hash,MINIMAL,m,delete
# 
# Config::Ini,AVATAR,m,delete
# 
# Config::Model::TkUi,DDUMONT,f,delete
# Config::Model::TkUI,DDUMONT,m,f
# 
# Config::Properties,RANDY,f,c
# Config::Properties,SALVA,m,f
# 
# ConfigReader::Simple,GOSSAMER,f,c
# ConfigReader::Simple,BDFOY,m,f
# 
# DBA::Backup::MySQL,SEANQ,f,delete
# DBA::Backup::mysql,SEANQ,m,f
# 
# DBD::google,DARREN,c,delete
# DBD::google,STENNIE,f,delete
# DBD::Google,DARREN,m,f
# 
# DBD::SQLrelay,DMOW,m,delete
# 
# DBD::Cego,COMPLX,f,delete
# DBD::cego,COMPLX,m,f
# 
# DBIx::XMLMEssage,ANDREIN,m,delete
# 
# Des,MICB,m,delete
# DES,EAYNG,m,f
# 
# Data::Report,AORR,f,c
# Data::Report,JV,m,f
# 
# Devel::Strace,DARNOLD,m,delete
# 
# DirHandle,CHIPS,m,c
# 
# Facebook::OpenGraph,BARTENDER,f,c
# Facebook::OpenGraph,OKLAHOMER,m,f
# 
# Fcntl,JHI,m,c
# 
# File::Remove,SHLOMIF,f,c
# File::Remove,RSOD,m,f
# 
# File::stat,TOMC,m,c
# 
# Filesys::statfs,TOMC,m,delete
# 
# Fortran::NameList,SGEL,m,delete
# 
# GX,JAU,m,delete
# 
# Games::Go::SGF,SAMTREGAR,f,delete
# Games::Go::SGF,DEG,m,f
# 
# Games::PerlWar,YANICK,f,delete
# Games::Perlwar,YANICK,m,f
# 
# HG,RTWARD,m,delete
# 
# HTTP::Body,MRAMBERG,f,c
# HTTP::Body,CHANSEN,m,f
# 
# HTTP::Request::AsCGI,MRAMBERG,f,c
# HTTP::Request::AsCGI,CHANSEN,m,f
# 
# Hailo,HINRIK,f,c
# Hailo,AVAR,m,f
# 
# I18N::Collate,JHI,m,c
# 
# Image::EPEG,MCURTIS,f,delete
# Image::EPEG,TOKUHIROM,c,delete
# Image::Epeg,MCURTIS,m,f
# 
# Javascript,FGLOCK,f,c
# JavaScript,CLAESJAC,m,f
# 
# Labkey::Query,BBIMBER,m,delete
# Labkey::Query,LABKEY,c,delete
# Labkey::query,BBIMBER,m,delete
# 
# ngua::PT::pln,AMBS,f,delete
# Lingua::PT::PLN,AMBS,m,delete
# 
# Marc,FREDERICD,f,delete
# MARC,PERL4LIB,m,f
# 
# Marc::Record,FREDERICD,f,delete
# MARC::Record,MIKERY,m,f
# 
# Math::BigFloat,TELS,m,c
# 
# Math::BigInt,TELS,m,c
# 
# Math::Complex,RAM,m,c
# Math::Complex,ZEFRAM,f,c
# Math::Complex,P5P,f,add
# 
# Math::Geometry::Planar::Offset,DVDPOL,f,c
# Math::Geometry::Planar::Offset,EWILHELM,m,f
# 
# Mobile::Wurfl,AWRIGLEY,f,c
# Mobile::WURFL,VALDEZ,m,f
# 
# Mojolicious::Plugin::deCSRF,SYSADM,m,delete
# 
# Nagios::Nrpe,AVERNA,f,c
# Nagios::NRPE,AMARSCHKE,m,f
# 
# Net::CouchDB,MNF,m,f
# 
# Net::MitM,BAVELING,m,delete
# 
# Net::Oscar,SLAFF,m,delete
# Net::OSCAR,MATTHEWG,m,f
# 
# Net::hostent,TOMC,m,c
# 
# Net::netent,TOMC,m,c
# 
# Net::protoent,TOMC,m,c
# 
# Net::servent,TOMC,m,c
# 
# o,DAMS,f,delete
# O,MICB,m,c
# O,P5P,f,add
# 
# Ox,KJM,m,delete
# 
# Pdf,KAARE,f,delete
# PDF,ANTRO,m,f
# 
# PDL::IO::HDF5,CHM,f,c
# PDL::IO::HDF5,CERNEY,m,f
# 
# Panda,SYBER,m,delete
# 
# Parse::YAPP::KeyValue,DIZ,m,delete
# 
# next line changed by andk from drop to delete, presuming this was meant
# PerlMenu,SKUNZ,m,delete
# 
# Pod::HTML,KJALB,m,c
# 
# Pod::Latex,KJALB,m,delete
# 
# Pod::Rtf,PVHP,f,c
# Pod::RTF,KJALB,m,f
# 
# Pod::SpeakIT::MacSpeech,BDFOY,m,delete
# 
# Pod::Text,TOMC,m,c
# 
# protect,JDUNCAN,f,delete
# Protect,JDUNCAN,m,f
# 
# QT,CDAWSON,f,c
# Qt,AWIN,m,f
# 
# RT::Extension::MenubarUserTickets,DUMB,m,delete
# 
# RWDE,DAMJANP,f,c
# RWDE,VKHERA,m,f
# 
# readonly,BDFOY,f,delete
# Readonly,ROODE,m,f
# 
# Remedy::AR,RIK,m,delete
# 
# SMS::Send::TW::Emome,SNOWFLY,m,delete
# 
# super,DROLSKY,f,delete
# SUPER,P5P,m,delete
# 
# SVN::Look,DMUEY,m,c
# 
# Sane,RATCLIFFE,m,c
# 
# Search::Glimpse,MIKEH,f,c
# Search::Glimpse,AMBS,m,f
# 
# SelectSaver,CHIPS,m,c
# 
# Sendmail::M4::mail8,CML,m,delete
# 
# Socket,GNAT,m,c
# 
# Symbol,CHIPS,m,c
# 
# SYS::lastlog,TOMC,f,delete
# Sys::Lastlog,JSTOWE,m,f
# 
# template,ABALAMA,f,delete
# Template,ABW,m,f
# 
# Term::Cap,TSANDERS,m,c
# 
# Term::ReadLine,ILYAZ,m,c
# 
# Test::Cucumber,JOHND,f,c
# Test::Cucumber,SARGIE,m,f
# 
# Text::Banner,LORY,m,c
# Text::Capitalize,SYP,m,c
# 
# Text::ParseWords,CHORNY,m,c
# 
# Text::Soundex,MARKM,m,c
# 
# Thesaurus::DBI,DROLSKY,f,c
# Thesaurus::DBI,JOSEIBERT,m,f
# 
# Tie::SentientHash,ADOPTME,f,delete
# Tie::SentientHash,ANDREWF,m,delete
# 
# Tie::SubstrHash,LWALL,m,c
# 
# Time::Format,PGOLLUCCI,f,delete
# Time::Format,ROODE,m,c
# 
# Time::gmtime,TOMC,m,c
# Time::localtime,TOMC,m,c
# 
# Tk::CheckBox,DKWILSON,m,c
# 
# Tk::Pod,TKML,m,c
# 
# Tk::Statusbar,ZABEL,m,delete
# 
# TUXEDO,AFRYER,f,delete
# Tuxedo,AFRYER,m,f
# 
# UUID,BRAAM,f,c
# UUID,JRM,m,f
# 
# User::grent,TOMC,m,c
# 
# User::pwent,TOMC,m,c
# 
# VCS::CVS,RSAVAGE,m,delete
# VCS::CVS,ETJ,c,delete
# 
# VMS::Filespec,CBAIL,m,c
# 
# VMS::Fileutils::Root,CLANE,m,delete
# 
# VMS::Fileutils::SafeName,CLANE,m,delete
# 
# Wait,JACKS,f,delete
# WAIT,ULPFR,m,f
# 
# WING,MICB,m,delete
# 
# WWW::AllTop,ARNIE,f,delete
# WWW::Alltop,ARNIE,m,f
# 
# WWW::Search::Google,MTHURN,f,c
# WWW::Search::Google,LBROCARD,m,f
# 
# WWW::Tamperdata,MARCUSSEN,m,delete
# 
# WebService::NMA,CHISEL,f,delete
# WebService::NMA,SHUFF,m,f
# 
# WebService::Rakuten,DRAWNBOY,f,c
# WebService::Rakuten,DYLAN,m,f
# 
# Webservice::Instagram,DAYANUNE,m,delete
# 
# Webservice::Tesco::API,WBASSON,m,delete
# 
# Webservice::Vtiger,MONSENHOR,m,delete
# 
# Xbase,PRATP,f,delete
# XBase,JANPAZ,m,f
# 
# Xml,SAKOHT,f,c
# XML,XMLML,m,f
# 
# XML::LibXML,PHISH,m,c
# 
# XML::Smart,GMPASSOS,f,c
# XML::Smart,TMHARISH,m,f
# 
# diagnostics,TOMC,m,c
# 
# overload,ILYAZ,m,c
# 
# VERSION,LEIF,f,delete
# Version,ASKSH,f,delete
# version,JPEACOCK,m,f
B::C,MICB,f,c
B::C,RURBAN,m,f
Apache::test,APML,m,delete
