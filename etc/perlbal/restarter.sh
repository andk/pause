#!/bin/sh

set -e

for domain in $RENEWED_DOMAINS; do
        case $domain in
        pause.perl.org)
                /etc/init.d/PAUSE-perlbal restart
                ;;
        esac
done
