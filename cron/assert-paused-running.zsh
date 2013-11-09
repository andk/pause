#!/bin/zsh

if ! /etc/init.d/PAUSE-paused status > /dev/null ; then
  /etc/init.d/PAUSE-paused start
fi
