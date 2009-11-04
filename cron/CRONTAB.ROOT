MAILTO=k
PATH=/usr/bin:/bin:/home/k/PAUSE/cron:/usr/local/bin

26 * * * *            mldistwatch --logfile /var/log/mldistwatch.cron.log
16 15,21,03,09 * * *  update-checksums.pl
46 * * * *            find /home/ftp/pub/PAUSE/authors/id -name 'CHECKSUMS.????'
45 * * * *            find /home/ftp/pub/PAUSE/authors/id -name CHECKSUMS -exec perl -c {} \; 2>&1 | grep -v OK | cat
* * * * *             date -u > /home/ftp/tmp/02STAMP && mv /home/ftp/tmp/02STAMP /home/ftp/pub/PAUSE/authors/02STAMP && /usr/local/perl-5.10.0-RC2/bin/perl -I /home/k/pause/lib -e 'use PAUSE; PAUSE::newfile_hook(shift)' /home/ftp/pub/PAUSE/authors/02STAMP
* * * * *             recentfile-aggregate.sh
*/5 * * * *           threeware_root.sh
# */2 * * * *           csync-wrapper.pl -G pause_perl_org -update
# 31 * * * *            csync-wrapper.pl --check
29 * * * *            cleanup-incoming.pl
19 06,18 * * *        cron-daily.pl
37 05 * * *           gmls-lR.pl
47 05,11,17,23 * * *  mysql-dump.pl
4,56 * * * *          session-backup.zsh
19 * * * *            make-mirror-yaml.pl
19,49 * * * *         publish-crontab.sh
38 04 * * 7           restart-httpd
21 * * * *            rm_stale_links
#22,52 * * * *         mail-stats.pl
23 05,11,17,23 * * *  run_mirrors.sh
#23 10 * * *           svn-dump.pl
22 * * * *            sync-04pause.pl
# 27 3,15 * * *         rsync --exclude CHECKSUMS -vrptgx /home/ftp/pub/PAUSE/authors/id/ /home/ftp/pub/backpan/authors/id/ && date
