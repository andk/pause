#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib/", "$FindBin::Bin/lib/pause_2017", "$FindBin::Bin/lib/pause_2025", "$FindBin::Bin/../pause-private/lib", "$FindBin::Bin/privatelib";
use Plack::Builder;
use Plack::App::Directory::Apaxy;
use Path::Tiny;
my $AppRoot = path(__FILE__)->parent->realpath;
Log::Dispatch::Config->configure("$AppRoot/etc/plack_log.conf.".($ENV{PLACK_ENV} // 'development'));

$ENV{MOJO_REVERSE_PROXY} = 1;
$ENV{MOJO_HOME} = $AppRoot;

# preload stuff
use PAUSE::Web::Context;
use PAUSE::Web;
use PAUSE::Web::App::Index;
use PAUSE::Web::App::Disabled;
use PAUSE::Web2025;
use PAUSE::Web2025::Context;

use BSD::Resource ();
#BSD::Resource::setrlimit(BSD::Resource::RLIMIT_CPU(),
#                         60*10, 60*10);
#BSD::Resource::setrlimit(BSD::Resource::RLIMIT_DATA(),
#                         40*1024*1024, 40*1024*1024);
BSD::Resource::setrlimit(BSD::Resource::RLIMIT_CORE(),
                         40*1024*1024, 40*1024*1024);

my $builder = eval {

my $context = PAUSE::Web::Context->new(root => $AppRoot);
$context->init;

my $context2025 = PAUSE::Web2025::Context->new(root => $AppRoot);
$context2025->init;

my $pause_app = PAUSE::Web->new(pause => $context);
my $pause2025_app = PAUSE::Web2025->new(pause => $context2025);
my $disabled_app = PAUSE::Web::App::Disabled->new->to_app;

builder {
  enable 'LogDispatch', logger => $context->logger;
  enable 'ReverseProxy';
  enable 'ServerStatus::Tiny', path => '/status';

  if (-f "/etc/PAUSE.CLOSED") {
    mount '/' => builder { $disabled_app };
  } else {
    # Static files are serverd by us; maybe some day we want to change that
    enable 'Static',
        path => qr{(?:(?<!index)\.(js|css|gif|jpg|png|pod|html)$|^/\.well-known/)},
        root => "$FindBin::Bin/htdocs";

    mount '/pub/PAUSE' => builder {
        enable '+PAUSE::Web::Middleware::Auth::Basic', context => $context;
        Plack::App::Directory::Apaxy->new(root => $PAUSE::Config->{FTPPUB});
    };

    mount '/incoming' => builder {
        enable '+PAUSE::Web::Middleware::Auth::Basic', context => $context;
        Plack::App::Directory::Apaxy->new(root => $PAUSE::Config->{INCOMING_LOC});
    };

    mount '/pause' => builder {
        enable_if {$_[0]->{PATH_INFO} =~ /authenquery/ ? 1 : 0} '+PAUSE::Web::Middleware::Auth::Basic', context => $context;
        $pause_app->start('psgi');
    };

    mount '/' => builder {
        $pause2025_app->start('psgi');
    };
  }
};

};

if ($@) {
  Log::Dispatch::Config->instance->log(
    level => 'error',
    message => "$@",
  );
}

$builder;
