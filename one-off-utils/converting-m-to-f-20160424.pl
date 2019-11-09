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

When we reached circa line 335 of the list after the DATA filehandle,
we discovered the need to have the upgrade c=>f option too and
implemented it:

        f       downgrade m=>f or upgrade c=>f

head2 EXAMPLES

 AI::nnflex,CCOLBOURN,f,delete
 AI::NNFlex,CCOLBOURN,m,f
 Tk::Pod,TKML,m,c
 Tk::Statusbar,ZABEL,m,delete
 Time::Format,ROODE,c,f
 JSON::Assert,SGREEN,f,add
 Net::MAC::Vendor,ETHER,f,add
 Sane,PABLROD,f,delete
 Algorithm::LCS,ADOPTME,f,add

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
    for ($m,$a,$type,$action) {
        s/\s//g;
    }
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
                warn "Inserting into perms modid=$m,userid=$a (may fail with 'Duplicate entry')";
                $sth4->execute($m,$a);
            }
        } elsif ($type eq "f") {
            if ($Opt{"dry-run"}){
                warn "Would delete first-come 2 AND Would insert comaint 2\n";
            } else {
                warn "Deleting from primeur package=$m,userid=$a";
                $sth2->execute($m,$a);
                warn "Inserting into perms modid=$m,userid=$a (may fail with 'Duplicate entry')";
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
        } elsif ($type eq "c") {
            if ($Opt{"dry-run"}){
                warn "Would delete comaint AND Would insert first-come\n";
            } else {
                warn "Deleting from perms package=$m,userid=$a";
                $sth3->execute($m,$a);
                warn "Inserting into primeur modid=$m,userid=$a";
                $sth5->execute($m,$a);
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
        } elsif ($type eq "c") {
            if ($Opt{"dry-run"}){
                warn "Would insert comaint 3\n";
            } else {
                warn "Inserting into perms modid=$m,userid=$a (may fail with 'Duplicate entry')";
                $sth4->execute($m,$a);
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
# Plack::Middleware::LogErrors::LogHandle,ADOPTME,f,delete
Benchmark::Thread::Size,ELIZABETH,f,delete
Benchmark::Thread::Size,LNATION,f,add
Benchmark::Thread::Size,HANDOFF,c,delete

Cache::Memcached::Managed,ELIZABETH,f,delete
Cache::Memcached::Managed,LNATION,f,add
Cache::Memcached::Managed,HANDOFF,c,delete

Cache::Memcached::Managed::Inactive,ELIZABETH,f,delete
Cache::Memcached::Managed::Inactive,LNATION,f,add
Cache::Memcached::Managed::Inactive,HANDOFF,c,delete

Cache::Memcached::Managed::Multi,ELIZABETH,f,delete
Cache::Memcached::Managed::Multi,LNATION,f,add
Cache::Memcached::Managed::Multi,HANDOFF,c,delete

Class::ExtraAttributes,ELIZABETH,f,delete
Class::ExtraAttributes,LNATION,f,add
Class::ExtraAttributes,HANDOFF,c,delete

Data::Reuse,ELIZABETH,f,delete
Data::Reuse,LNATION,f,add
Data::Reuse,HANDOFF,c,delete

Devel::MaintBlead,ELIZABETH,f,delete
Devel::MaintBlead,LNATION,f,add
Devel::MaintBlead,HANDOFF,c,delete

Devel::Required,ELIZABETH,f,delete
Devel::Required,LNATION,f,add
Devel::Required,HANDOFF,c,delete

Devel::ThreadsForks,ELIZABETH,f,delete
Devel::ThreadsForks,LNATION,f,add
Devel::ThreadsForks,HANDOFF,c,delete

IOLayer::Base64,ELIZABETH,f,delete
IOLayer::Base64,LNATION,f,add
IOLayer::Base64,HANDOFF,c,delete

IOLayer::MD5,ELIZABETH,f,delete
IOLayer::MD5,LNATION,f,add
IOLayer::MD5,HANDOFF,c,delete

IOLayer::QuotedPrint,ELIZABETH,f,delete
IOLayer::QuotedPrint,LNATION,f,add
IOLayer::QuotedPrint,HANDOFF,c,delete

LCC,ELIZABETH,f,delete
LCC,LNATION,f,add
LCC,HANDOFF,c,delete

LCC::Backend,ELIZABETH,f,delete
LCC::Backend,LNATION,f,add
LCC::Backend,HANDOFF,c,delete

LCC::Backend::DBI,ELIZABETH,f,delete
LCC::Backend::DBI,LNATION,f,add
LCC::Backend::DBI,HANDOFF,c,delete

LCC::Backend::DBI::mysql,ELIZABETH,f,delete
LCC::Backend::DBI::mysql,LNATION,f,add
LCC::Backend::DBI::mysql,HANDOFF,c,delete

LCC::Backend::Storable,ELIZABETH,f,delete
LCC::Backend::Storable,LNATION,f,add
LCC::Backend::Storable,HANDOFF,c,delete

LCC::Backend::textfile,ELIZABETH,f,delete
LCC::Backend::textfile,LNATION,f,add
LCC::Backend::textfile,HANDOFF,c,delete

LCC::Documents,ELIZABETH,f,delete
LCC::Documents,LNATION,f,add
LCC::Documents,HANDOFF,c,delete

LCC::Documents::DBI,ELIZABETH,f,delete
LCC::Documents::DBI,LNATION,f,add
LCC::Documents::DBI,HANDOFF,c,delete

LCC::Documents::filesystem,ELIZABETH,f,delete
LCC::Documents::filesystem,LNATION,f,add
LCC::Documents::filesystem,HANDOFF,c,delete

LCC::Documents::module,ELIZABETH,f,delete
LCC::Documents::module,LNATION,f,add
LCC::Documents::module,HANDOFF,c,delete

LCC::Documents::queue,ELIZABETH,f,delete
LCC::Documents::queue,LNATION,f,add
LCC::Documents::queue,HANDOFF,c,delete

LCC::UNS,ELIZABETH,f,delete
LCC::UNS,LNATION,f,add
LCC::UNS,HANDOFF,c,delete

Log::Dispatch::WarnDie,ELIZABETH,f,delete
Log::Dispatch::WarnDie,LNATION,f,add
Log::Dispatch::WarnDie,HANDOFF,c,delete

Log::Dispatch::XML,ELIZABETH,f,delete
Log::Dispatch::XML,LNATION,f,add
Log::Dispatch::XML,HANDOFF,c,delete

OOB,ELIZABETH,f,delete
OOB,LNATION,f,add
OOB,HANDOFF,c,delete

OOB::function,ELIZABETH,f,delete
OOB::function,LNATION,f,add
OOB::function,HANDOFF,c,delete

PerlIO::via::Base64,ELIZABETH,f,delete
PerlIO::via::Base64,LNATION,f,add
PerlIO::via::Base64,HANDOFF,c,delete

PerlIO::via::Include,ELIZABETH,f,delete
PerlIO::via::Include,LNATION,f,add
PerlIO::via::Include,HANDOFF,c,delete

PerlIO::via::LineNumber,ELIZABETH,f,delete
PerlIO::via::LineNumber,LNATION,f,add
PerlIO::via::LineNumber,HANDOFF,c,delete

PerlIO::via::MD5,ELIZABETH,f,delete
PerlIO::via::MD5,LNATION,f,add
PerlIO::via::MD5,HANDOFF,c,delete

PerlIO::via::Pod,ELIZABETH,f,delete
PerlIO::via::Pod,LNATION,f,add
PerlIO::via::Pod,HANDOFF,c,delete

PerlIO::via::Rotate,ELIZABETH,f,delete
PerlIO::via::Rotate,LNATION,f,add
PerlIO::via::Rotate,HANDOFF,c,delete

PerlIO::via::UnComment,ELIZABETH,f,delete
PerlIO::via::UnComment,LNATION,f,add
PerlIO::via::UnComment,HANDOFF,c,delete

PerlIO::via::UnPod,ELIZABETH,f,delete
PerlIO::via::UnPod,LNATION,f,add
PerlIO::via::UnPod,HANDOFF,c,delete

String::Lookup,ELIZABETH,f,delete
String::Lookup,LNATION,f,add
String::Lookup,HANDOFF,c,delete

Sys::RunAlone,ELIZABETH,c,delete
Sys::RunAlone,LNATION,c,add
Sys::RunAlone,HANDOFF,c,delete

Sys::RunAlways,ELIZABETH,c,delete
Sys::RunAlways,LNATION,c,add
Sys::RunAlways,HANDOFF,c,delete

Sys::RunUntil,ELIZABETH,c,delete
Sys::RunUntil,LNATION,c,add
Sys::RunUntil,HANDOFF,c,delete

Thread::Bless,ELIZABETH,f,delete
Thread::Bless,LNATION,f,add
Thread::Bless,HANDOFF,c,delete

Thread::Conveyor,ELIZABETH,f,delete
Thread::Conveyor,LNATION,f,add
Thread::Conveyor,HANDOFF,c,delete

Thread::Conveyor::Monitored,ELIZABETH,f,delete
Thread::Conveyor::Monitored,LNATION,f,add
Thread::Conveyor::Monitored,HANDOFF,c,delete

Thread::Deadlock,ELIZABETH,f,delete
Thread::Deadlock,LNATION,f,add
Thread::Deadlock,HANDOFF,c,delete

Thread::Exit,ELIZABETH,f,delete
Thread::Exit,LNATION,f,add
Thread::Exit,HANDOFF,c,delete

Thread::Needs,ELIZABETH,f,delete
Thread::Needs,LNATION,f,add
Thread::Needs,HANDOFF,c,delete

Thread::Queue::Any,ELIZABETH,f,delete
Thread::Queue::Any,LNATION,f,add
Thread::Queue::Any,HANDOFF,c,delete

Thread::Queue::Any::Monitored,ELIZABETH,f,delete
Thread::Queue::Any::Monitored,LNATION,f,add
Thread::Queue::Any::Monitored,HANDOFF,c,delete

Thread::Queue::Monitored,ELIZABETH,f,delete
Thread::Queue::Monitored,LNATION,f,add
Thread::Queue::Monitored,HANDOFF,c,delete

Thread::Rand,ELIZABETH,f,delete
Thread::Rand,LNATION,f,add
Thread::Rand,HANDOFF,c,delete

Thread::Running,ELIZABETH,f,delete
Thread::Running,LNATION,f,add
Thread::Running,HANDOFF,c,delete

Thread::Serialize,ELIZABETH,f,delete
Thread::Serialize,LNATION,f,add
Thread::Serialize,HANDOFF,c,delete

Thread::Status,ELIZABETH,f,delete
Thread::Status,LNATION,f,add
Thread::Status,HANDOFF,c,delete

Thread::Synchronized,ELIZABETH,f,delete
Thread::Synchronized,LNATION,f,add
Thread::Synchronized,HANDOFF,c,delete

Thread::Tie,ELIZABETH,f,delete
Thread::Tie,LNATION,f,add
Thread::Tie,HANDOFF,c,delete

Thread::Tie::Array,ELIZABETH,f,delete
Thread::Tie::Array,LNATION,f,add
Thread::Tie::Array,HANDOFF,c,delete

Thread::Tie::Handle,ELIZABETH,f,delete
Thread::Tie::Handle,LNATION,f,add
Thread::Tie::Handle,HANDOFF,c,delete

Thread::Tie::Hash,ELIZABETH,f,delete
Thread::Tie::Hash,LNATION,f,add
Thread::Tie::Hash,HANDOFF,c,delete

Thread::Tie::Scalar,ELIZABETH,f,delete
Thread::Tie::Scalar,LNATION,f,add
Thread::Tie::Scalar,HANDOFF,c,delete

Thread::Tie::Thread,ELIZABETH,f,delete
Thread::Tie::Thread,LNATION,f,add
Thread::Tie::Thread,HANDOFF,c,delete

Thread::Use,ELIZABETH,f,delete
Thread::Use,LNATION,f,add
Thread::Use,HANDOFF,c,delete

UNIVERSAL::dump,ELIZABETH,f,delete
UNIVERSAL::dump,LNATION,f,add
UNIVERSAL::dump,HANDOFF,c,delete

ifdef,ELIZABETH,f,delete
ifdef,LNATION,f,add
ifdef,HANDOFF,c,delete

load,ELIZABETH,f,delete
load,LNATION,f,add
load,HANDOFF,c,delete

persona,ELIZABETH,f,delete
persona,LNATION,f,add
persona,HANDOFF,c,delete

setenv,ELIZABETH,f,delete
setenv,LNATION,f,add
setenv,HANDOFF,c,delete
