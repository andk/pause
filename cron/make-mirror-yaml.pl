#!/usr/local/bin/perl

use strict;
use warnings;
use CPAN::Indexer::Mirror 0.05; # atomic writes
use File::Path qw(mkpath);
use LWP::UserAgent;

use lib "/home/k/PAUSE/lib", "/home/k/dproj/PAUSE/wc/lib";
use PAUSE;

die "FTP_RUN not defined" unless defined $PAUSE::Config->{FTP_RUN};
my $rundir = "$PAUSE::Config->{FTP_RUN}/mirroryaml";
mkpath $rundir;
my $ua = LWP::UserAgent->new(agent => "PAUSE/20080922");
my $resp = $ua->mirror("ftp://ftp.funet.fi/pub/languages/perl/CPAN/MIRRORED.BY","$rundir/MIRRORED.BY");
die "Could not mirror: ".$resp->status_line unless $resp->is_success || 304 eq $resp->code;

CPAN::Indexer::Mirror->new(
                           root => $rundir,
                          )->run;
