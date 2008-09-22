#!/usr/local/bin/perl

use strict;
use warnings;
use CPAN::Indexer::Mirror;
use File::Path qw(mkpath);
use LWP::UserAgent;

use lib "/home/k/PAUSE/lib";
use PAUSE;

my $rundir = "$PAUSE::Config->{FTP_RUN}/mirroryaml";
mkpath $rundir;
my $ua = LWP::UserAgent->new(agent => "PAUSE/20080922");
my $resp = $ua->mirror("ftp://ftp.funet.fi/pub/languages/perl/CPAN/MIRRORED.BY","$rundir/MIRRORED.BY");
die "Could not mirror: ".$resp->code unless $resp->is_success;

CPAN::Indexer::Mirror->new(
                           root => $rundir,
                          )->run;
