#!/bin/zsh

set -e

# set -x

rsync -a ~k/PAUSE/htdocs/04pause.html ~ftp/pub/PAUSE/modules/
