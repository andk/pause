#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Plack::Builder;
use Plack::Request;
use Log::Contextual::SimpleLogger;

# preload stuff
use pause_1999::config;

my $logger = Log::Contextual::SimpleLogger->new({
    ident => 'pause',
    to_stderr => 1,
    debug => 1,
});

my $app = sub {
    my $req = Plack::Request->new(shift);
    pause_1999::config::handler($req);
};

builder {
    # enable Session, Auth, Log, etc with better config
    enable 'Log::Contextual', logger => $logger;
    $app;
};
