#!/bin/zsh

set -e

# set -x

rsync -a ~k/pause/htdocs/0*.html ~ftp/pub/PAUSE/modules/
