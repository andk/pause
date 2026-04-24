#!/bin/bash
set -e

mkdir -p \
    /pause-run/tmp \
    /pause-run/pid \
    /pause-run/log \
    /pause-run/rundata/session

mkdir -p \
    /data/pause/ftp \
    /data/pause/tmp \
    /data/pause/incoming \
    /data/pause/pub/PAUSE/PAUSE-git \
    /data/pause/pub/PAUSE/PAUSE-data \
    /data/pause/pub/PAUSE/modules \
    /data/pause/pub/PAUSE/authors/id

chown -R pause: /pause-run
chown -R pause: /data

