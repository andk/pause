#!/bin/zsh

set -e

# set -x

/usr/local/bin/rsync -a ~k/PAUSE/htdocs/04pause.html ~ftp/pub/PAUSE/modules/
