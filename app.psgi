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
use pause_1999::index;
use pause_1999::fixup;
use perl_pause::disabled2;

my $logger = Log::Dispatch->new(outputs => [
    ['Screen', min_level => 'debug'],
]);

use BSD::Resource ();
#BSD::Resource::setrlimit(BSD::Resource::RLIMIT_CPU(),
#                         60*10, 60*10);
#BSD::Resource::setrlimit(BSD::Resource::RLIMIT_DATA(),
#                         40*1024*1024, 40*1024*1024);
BSD::Resource::setrlimit(BSD::Resource::RLIMIT_CORE(),
                         40*1024*1024, 40*1024*1024);

my $pause_app = sub {
    my $req = Plack::Request->new(shift);

    if (-f "/etc/PAUSE.CLOSED") {
        return perl_pause::disabled2::handler($req);
    }

    my $res =
#        pause_1999::fixup::handler($req) //
        pause_1999::config::handler($req);
    return $res if ref $res;
    [$res =~ /^\d+$/ ? $res : 500, [], [$res]];
};

my $index_app = sub {
    my $req = Plack::Request->new(shift);
    my $res = pause_1999::index::handler($req);
    return $res if ref $res;
    [$res =~ /^\d+$/ ? $res : 500, [], [$res]];
};

builder {
    enable 'LogDispatch', logger => $logger;
    enable 'AccessLog::Timed', format => 'combined';
    enable 'ReverseProxy';
#    enable_if {$_[0]->{REMOTE_ADDR} eq '127.0.0.1'} 'ReverseProxy';
#    enable 'ErrorDocument',
#        500 => '',
#        404 => '',
#        403 => '',
#    ;
    enable 'ServerStatus::Tiny', path => '/status';

    mount '/pause' => builder {
        enable_if {$_[0]->{PATH_INFO} =~ /authenquery/ ? 1 : 0} '+PAUSE::Middleware::Auth::Basic';
        $pause_app;
    };

#    mount '/' => builder { $index_app };
};
