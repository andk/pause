MAILTO=k
PATH=/usr/bin:/bin:/home/k/PAUSE/cron:/usr/local/bin

* * * * *             date -u > /home/ftp/tmp/02STAMP && mv /home/ftp/tmp/02STAMP /home/ftp/pub/PAUSE/authors/02STAMP
29 * * * *            cleanup-incoming.pl
29 09,21 * * *        cron-daily.pl
37 05 * * *           gmls-lR.pl
40 * * * *            mldistwatch
18 03,09,15,21 * * *  mysql-dump.pl
19,49 * * * *         publish-crontab.sh
20 01 * * 7           restart-httpd
21 * * * *            rm_stale_links
22,52 * * * *         mail-stats.pl
23 05,11,17,23 * * *  run_mirrors.sh
23 10 * * *           svn-dump.pl
24 * * * *            sync-04pause.sh
24 */4 * * *          update-checksums.pl
27 3,15 * * *         rsync --exclude CHECKSUMS -vrptgx /home/ftp/pub/PAUSE/authors/id/ /home/ftp/pub/backpan/authors/id/ && date
