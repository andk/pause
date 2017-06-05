#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Plack::Builder;
use Plack::Request;
use Plack::App::Directory::Apaxy;
use Log::Dispatch::Config;

Log::Dispatch::Config->configure("etc/plack_log.conf.".($ENV{PLACK_ENV} // 'development'));

# preload stuff
use pause_1999::config;
use pause_1999::index;
use pause_1999::fixup;
use perl_pause::disabled2;

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
        pause_1999::fixup::handler($req) //
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
    enable 'LogDispatch', logger => Log::Dispatch::Config->instance;
#    enable 'AccessLog::Timed', format => 'combined';
    enable 'ReverseProxy';
#    enable_if {$_[0]->{REMOTE_ADDR} eq '127.0.0.1'} 'ReverseProxy';
#    enable 'ErrorDocument',
#        500 => '',
#        404 => '',
#        403 => '',
#    ;
    enable 'ServerStatus::Tiny', path => '/status';

    # Static files should not be served by application server actually.
    # This is only for testing/developing.
    enable 'Static',
        path => qr{(?:(?<!index)\.(js|css|gif|jpg|png|pod|html)$|^/\.well-known/)},
        root => "$FindBin::Bin/htdocs";

    mount '/pub/PAUSE' => builder {
        enable '+PAUSE::Middleware::Auth::Basic';
        Plack::App::Directory::Apaxy->new(root => $PAUSE::Config->{FTPPUB});
    };

    mount '/incoming' => builder {
        enable '+PAUSE::Middleware::Auth::Basic';
        Plack::App::Directory::Apaxy->new(root => $PAUSE::Config->{INCOMING_LOC});
    };

    mount '/pause' => builder {
        enable_if {$_[0]->{PATH_INFO} =~ /authenquery/ ? 1 : 0} '+PAUSE::Middleware::Auth::Basic';
        $pause_app;
    };

    mount '/' => builder { $index_app };
};
