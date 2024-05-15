MAILTO=andreas.koenig.5c1c1wmb@franz.ak.mind.de

PATH=/home/pause/.plenv/shims:/usr/bin:/home/pause/pause/cron
PAUSE_REPO=/home/pause/pause
PAUSE_ROOT=/data/pause/pub/PAUSE

* * * * *             pause  $PAUSE_REPO/cron/recentfile-aggregate

# some kind of PAUSE heartbeat/health check system?
* * * * *             pause  date -u +"\%s \%a \%b \%e \%T \%Z \%Y" > /tmp/02STAMP && mv /tmp/02STAMP $PAUSE_ROOT/authors/02STAMP && perl -I $PAUSE_REPO/lib -e 'use PAUSE; PAUSE::newfile_hook(shift)' $PAUSE_ROOT/authors/02STAMP
08 * * * *            pause  date -u +"\%s \%FT\%TZ" > /tmp/02STAMPm && mv /tmp/02STAMPm $PAUSE_ROOT/modules/02STAMP && perl -I $PAUSE_REPO/lib -e 'use PAUSE; PAUSE::newfile_hook(shift)' $PAUSE_ROOT/modules/02STAMP

# THE INDEXER
52 * * * *            pause  $PAUSE_REPO/cron/mldistwatch --logfile /home/pause/log/mldistwatch.cron.log
04 7 * * 6            pause  $PAUSE_REPO/cron/mldistwatch --logfile /home/pause/log/mldistwatch.cron.log --symlinkinventory
17,29,41,53 * * * *   pause  $PAUSE_REPO/cron/mldistwatch --logfile /home/pause/log/mldistwatch.cron.log --fail-silently-on-concurrency-protection --rewrite

12 06,14,22 * * *     pause  $PAUSE_REPO/cron/update-checksums.pl
29 * * * *            pause  $PAUSE_REPO/cron/cleanup-incoming.pl
59 * * * *            pause  $PAUSE_REPO/cron/cron-daily.pl
37 05 * * *           pause  $PAUSE_REPO/cron/gmls-lR.pl
47 07,13,19,01 * * *  pause  $PAUSE_REPO/cron/mysql-dump.pl
21 */6 * * *          pause  $PAUSE_REPO/cron/rm_stale_links
22 * * * *            pause  $PAUSE_REPO/cron/sync-04pause.pl
10 09,15,21,03 * * *  pause  cd $PAUSE_ROOT/PAUSE-git && (git gc -q && git push -q -u origin master)
18 * * * *            pause  $PAUSE_REPO/cron/cron-p6daily.pl
