#!/bin/zsh

set -e

# set -x

/usr/local/bin/rsync -a ~k/PAUSE/ftpd/messages/incoming.txt ~ftp/incoming/.message
