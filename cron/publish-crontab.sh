#!/bin/sh

if ! cmp /var/spool/cron/root /home/k/PAUSE/cron/crontab.root ; then
    diff -u /home/k/PAUSE/cron/crontab.root /var/spool/cron/root
    echo
    echo END OF DIFF
    set -x
    cp /var/spool/cron/root /home/k/PAUSE/cron/crontab.root
    chmod 644 /home/k/PAUSE/cron/crontab.root
fi
