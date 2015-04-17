#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Plack::Builder;
use Plack::Request;

# preload stuff
use pause_1999::config;

my $app = sub {
    my $req = Plack::Request->new(shift);
    pause_1999::config::handler($req);
};

builder {
    # enable Session, Auth, Log, etc with better config
    $app;
};
