#!/bin/sh

if [ -d /home/puppet/pause/mirror ] ; then
  MIRRDIR=/home/puppet/pause/mirror
  MIRRCNF=mirror.defaults-pause-us
elif [ -d /home/k/PAUSE/mirror ] ; then
  MIRRDIR=/home/k/PAUSE/mirror
  MIRRCNF=mirror.defaults
else
  echo could not find MIRRDIR
  exit 1
fi

perl /usr/bin/mirror -C$MIRRDIR/$MIRRCNF $MIRRDIR/mymirror.config
