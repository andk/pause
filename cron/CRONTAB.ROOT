# MAILTO=andreas.koenig.5c1c1wmb@franz.ak.mind.de

PATH=/home/pause/.plenv/shims:/usr/bin:/home/pause/pause/cron
PAUSE_REPO=/home/pause/pause
PAUSE_ROOT=/home/pause/pub/PAUSE

## STUFF RJBS DID TO PUT THIS INTO UNPAUSE:
## * replace a bunch of paths:
##   * /opt/perl/current/bin with /usr/bin/perl
##   * put "perl" in front of things to use plenv perl instead of system perl
##   * put the pause repo's cron directory in path *and use it*
##
## …and we will write this to /etc/cron.d/SOMETHING

# ???
* * * * *             pause  $PAUSE_REPO/cron/recentfile-aggregate.sh

# some kind of PAUSE heartbeat/health check system?
* * * * *             pause  date -u +"\%s \%a \%b \%e \%T \%Z \%Y" > /tmp/02STAMP && mv /tmp/02STAMP $PAUSE_ROOT/authors/02STAMP && perl -I $PAUSE_REPO/lib -e 'use PAUSE; PAUSE::newfile_hook(shift)' $PAUSE_ROOT/authors/02STAMP
08 * * * *            pause  date -u +"\%s \%FT\%TZ" > /tmp/02STAMPm && mv /tmp/02STAMPm $PAUSE_ROOT/modules/02STAMP && perl -I $PAUSE_REPO/lib -e 'use PAUSE; PAUSE::newfile_hook(shift)' $PAUSE_ROOT/modules/02STAMP

# THE INDEXER
52 * * * *            pause  perl $PAUSE_REPO/cron/mldistwatch --logfile /var/log/mldistwatch.cron.log
04 7 * * 6            pause  perl $PAUSE_REPO/cron/mldistwatch --logfile /var/log/mldistwatch.cron.log --symlinkinventory
17,29,41,53 * * * *   pause  perl $PAUSE_REPO/cron/mldistwatch --logfile /var/log/mldistwatch.cron.log --fail-silently-on-concurrency-protection --rewrite

12 06,14,22 * * *     pause  perl $PAUSE_REPO/cron/update-checksums.pl
29 * * * *            pause  perl $PAUSE_REPO/cron/cleanup-incoming.pl
59 * * * *            pause  perl $PAUSE_REPO/cron/cron-daily.pl
37 05 * * *           pause  perl $PAUSE_REPO/cron/gmls-lR.pl
47 07,13,19,01 * * *  pause  perl $PAUSE_REPO/cron/mysql-dump.pl
19 * * * *            pause  perl $PAUSE_REPO/cron/make-mirror-yaml.pl
21 */6 * * *          pause  perl $PAUSE_REPO/cron/rm_stale_links
23 07,13,19,01 * * *  pause  perl run_mirrors.sh
22 * * * *            pause  perl $PAUSE_REPO/cron/sync-04pause.pl
10 09,15,21,03 * * *  pause  cd $PAUSE_ROOT/PAUSE-git && (git gc && git push -u origin master) >> /var/log/git-gc-push.out
18 * * * *            pause  perl $PAUSE_REPO/cron/cron-p6daily.pl
46 0,6,12,18 * * *    pause  perl -I $PAUSE_REPO/lib $PAUSE_REPO/bin/indexscripts.pl > $PAUSE_REPO/bin/indexscripts.pl.out 2>&1
7 2   * * 0           pause  perl -I $PAUSE_ROOT/lib $PAUSE_ROOT/bin/indexscripts.pl -f
4,11,19,26,34,42,49,56 * * * * pause  zsh $PAUSE_ROOT/cron/assert-paused-running.zsh

