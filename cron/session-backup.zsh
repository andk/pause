#!/usr/bin/zsh

set -e
cd /usr/local/apache/rundata/pause_1999/
ls -laR session > session-repo/ls-laR.txt
rsync -va session/ session-repo/ > session-repo/rsync.log
cd session-repo
git add **/*(.)
git commit -m backup
