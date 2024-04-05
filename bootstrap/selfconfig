#!/usr/bin/bash
set -e

cd ~pause

# install plenv so we can manage a local perl version
git clone https://github.com/tokuhirom/plenv.git ~/.plenv

echo 'export PATH="$HOME/.plenv/bin:$PATH"' >> ~/.bash_profile
echo 'eval "$(plenv init -)"' >> ~/.bash_profile
source ~/.bash_profile

# install perl-build so we can build a new perl
git clone https://github.com/tokuhirom/Perl-Build.git ~/.plenv/plugins/perl-build/

plenv install 5.36.0 -j 8
plenv global 5.36.0

# install cpanm for perl dep management
plenv install-cpanm

# We need to pin these for now
cpanm -n Mojolicious@8.72
cpanm -n DBD::mysql@4.052

cd ~pause/pause
cpanm -n --installdeps .

# Set up pause config
mkdir -p ~pause/pause-private/lib

cat << 'CONF' > ~pause/pause-private/lib/PrivatePAUSE.pm
use strict;
package PAUSE;

$ENV{EMAIL_SENDER_TRANSPORT} = 'DevNull';

our $Config;
$Config->{AUTHEN_DATA_SOURCE_USER}  = "pause";
$Config->{AUTHEN_DATA_SOURCE_PW}    = "pausepassword";
$Config->{MOD_DATA_SOURCE_USER}     = "pause";
$Config->{MOD_DATA_SOURCE_PW}       = "pausepassword";
$Config->{MAIL_MAILER}              = ["testfile"];
$Config->{RUNDATA}                  = "/tmp/pause_1999";

$Config->{CHECKSUMS_SIGNING_PROGRAM} = "does-not-exist";
$Config->{GITROOT} = '/home/pause/pub/PAUSE/PAUSE-git';
$Config->{MLROOT} = '/home/pause/pub/PAUSE/authors/id/';
$Config->{ML_CHOWN_USER}  = 'unsafe';
$Config->{ML_CHOWN_GROUP} = 'unsafe';
$Config->{ML_MIN_FILES} = 1;
$Config->{ML_MIN_INDEX_LINES} = 0;
$Config->{PAUSE_LOG} = "/home/pause/log/paused.log";
$Config->{PAUSE_LOG_DIR} = "/home/pause/log/";
$Config->{PID_DIR} = "/home/pause/pid/";
$Config->{TMP} = "/tmp/";
CONF

mkdir ~pause/log
mkdir ~pause/pid
mkdir -p ~pause/pub/PAUSE/authors/id
mkdir -p ~pause/pub/PAUSE/modules
mkdir -p ~pause/pub/PAUSE/PAUSE-git

cd ~pause/pub/PAUSE/PAUSE-git
git init
git config --global user.email "pause@pause.perl.org"
git config --global user.name "PAUSE Daemon"

mkdir -p /tmp/pause_1999
