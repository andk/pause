#!/usr/local/bin/perl

use strict;
use warnings;
use CPAN::Indexer::Mirror 0.05; # atomic writes
use File::Path qw(mkpath);
use LWP::UserAgent;

use FindBin;
use lib "$FindBin::Bin/../lib";
use PAUSE;

die "FTP_RUN not defined" unless defined $PAUSE::Config->{FTP_RUN};
my $rundir = "$PAUSE::Config->{FTP_RUN}/mirroryaml";
mkpath $rundir;
my $ua = LWP::UserAgent->new(agent => "PAUSE/20080922");
my $resp = $ua->mirror($PAUSE::Config->{MIRRORED_BY_URL},"$rundir/MIRRORED.BY");
die "Could not mirror: ".$resp->status_line unless $resp->is_success || 304 eq $resp->code;

CPAN::Indexer::Mirror->new(
                           root => $rundir,
                          )->run;
