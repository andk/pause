MAILTO=k
PATH=/usr/bin:/bin:/home/k/PAUSE/cron:/usr/local/bin

04 * * * *            cleanup-incoming.pl
04 01,13 * * *        cron-daily.pl
05 * * * *            gmls-lR.pl
36 * * * *            mldistwatch
18 04,10,16,22 * * *  mysql-dump.pl
19,49 * * * *         publish-crontab.sh
20 01 * * 7           restart-httpd
21 * * * *            rm_stale_links
23 05,11,17,23 * * *  run_mirrors.sh
26 10 * * *           svn-dump.pl
27 * * * *            sync-04pause.sh
28 */4 * * *          update-checksums.pl
32 3,15 * * *         rsync --exclude CHECKSUMS -vrptgx /home/ftp/pub/PAUSE/authors/id/ /home/ftp/pub/backpan/authors/id/
