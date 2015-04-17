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

sub authen_cb {
    my ($user, $pass, $env) = @_;
    my $req = Plack::Request->new($env);
    $req->session->{user} = $user;
    return 1;
}

builder {
    # enable Session, Auth, Log, etc with better config
    enable 'Log::Contextual', logger => $logger;
    enable 'Session', store => 'File';
    enable_if {$_[0]->{PATH_INFO} =~ /authenquery/ ? 1 : 0} 'Auth::Basic', authenticator => \&authen_cb;
    $app;
};
