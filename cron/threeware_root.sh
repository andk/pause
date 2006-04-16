#!/bin/sh

set -e

/usr/bin/tw_cli info `/usr/bin/tw_cli info | awk '/^c/{print $1}'` allunitstatus > /var/run/tw_cli.new
chmod 644 /var/run/tw_cli.new
mv /var/run/tw_cli.new /var/run/tw_cli
chmod 644 /var/run/tw_cli
