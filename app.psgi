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
    my $res = pause_1999::config::handler($req);
    return $res if ref $res;
    [$res =~ /^\d+$/ ? $res : 500, [], [$res]];
};

builder {
    # enable Session, Auth, Log, etc with better config
    mount '/pause' => builder {
        enable 'LogDispatch', logger => $logger;
        enable_if {$_[0]->{REMOTE_ADDR} eq '127.0.0.1'} 'ReverseProxy';
        enable_if {$_[0]->{PATH_INFO} =~ /authenquery/ ? 1 : 0} '+PAUSE::Middleware::Auth::Basic';
        enable 'ErrorDocument',
            500 => '',
            404 => '',
            403 => '',
        ;
        $app;
    },
    enable 'ServerStatus::Tiny', path => '/status';
};
