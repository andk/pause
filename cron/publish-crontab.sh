#!/bin/sh

if [ ! -d /home/k/PAUSE/tmp ] ; then
  mkdir /home/k/PAUSE/tmp
fi

CRONTMP=/home/k/PAUSE/tmp/crontab.root
CRONREPO=/home/k/PAUSE/cron/CRONTAB.ROOT

crontab -u root -l > $CRONTMP

if ! cmp $CRONTMP $CRONREPO ; then
    diff -u $CRONREPO $CRONTMP
    echo
    echo END OF DIFF
    set -x
    cp $CRONTMP $CRONREPO
    chmod 644 $CRONREPO
fi
