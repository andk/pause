#!/bin/zsh

set -e

# set -x

rsync -a ~k/PAUSE/htdocs/0*.html ~ftp/pub/PAUSE/modules/
