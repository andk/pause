#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Plack::Builder;
use Plack::Request;
use Log::Dispatch; # or better to use ::Config?

# preload stuff
use pause_1999::config;

my $logger = Log::Dispatch->new(outputs => [
    ['Screen', min_level => 'debug'],
]);

my $app = sub {
    my $req = Plack::Request->new(shift);
    pause_1999::config::handler($req);
};

builder {
    # enable Session, Auth, Log, etc with better config
    enable 'LogDispatch', logger => $logger;
    enable_if {$_[0]->{PATH_INFO} =~ /authenquery/ ? 1 : 0} '+PAUSE::Middleware::Auth::Basic';
    $app;
};
