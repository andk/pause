#!/bin/bash
set -e

for i in 1 2 3 4 5 6 7 8 9 10
do
    mysqladmin -h mysql -u pause --password=test ping > /dev/null 2>&1 && break
    sleep 10
done

if ! mysql -h mysql -u pause --password=test pause -e 'SELECT 1 FROM abrakadabra' > /dev/null 2>&1; then
	mysql -h mysql -u pause --password=test pause < ./doc/authen_pause.schema.txt
fi
if ! mysql -h mysql -u pause --password=test pause -e 'SELECT 1 FROM applymod' > /dev/null 2>&1; then
	mysql -h mysql -u pause --password=test pause < ./doc/mod.schema.txt
fi

echo "HEY!"
cd /root
tar xf /root/gnupg.tar.gz
cp -R /root/gnupg/* /root/.gnupg/
cd /home/k/pause
chmod 0600 /root/.gnupg/*
chmod 0600 /root/.gnupg/private-keys-v1.d
chmod 0600 /root/.gnupg/openpgp-revocs.d
chmod 0700 /root/.gnupg

perl -Ilib ./docker/app/insert_fixture.pl

if [ ! -d /home/ftp/incoming ]; then
	mkdir /home/ftp/incoming
fi
if [ ! -d /home/ftp/run ]; then
	mkdir /home/ftp/run
fi
if [ ! -d /home/ftp/pub/PAUSE ]; then
	mkdir /home/ftp/pub/PAUSE
fi
if [ ! -d /home/ftp/pub/PAUSE/PAUSE-git ]; then
    mkdir -p /home/ftp/pub/PAUSE/PAUSE-git
    cd /home/ftp/pub/PAUSE/PAUSE-git
    git init
    cd /home/k/pause
fi
if [ ! -d /home/ftp/pub/PAUSE/PAUSE-data ]; then
    mkdir -p /home/ftp/pub/PAUSE/PAUSE-data
fi
if [ ! -d /home/ftp/pub/PAUSE/modules ]; then
    mkdir -p /home/ftp/pub/PAUSE/modules
fi

cpm install -g

perl ./bin/paused --pidfile=/var/run/paused.pid &

plackup ./app_2017.psgi
