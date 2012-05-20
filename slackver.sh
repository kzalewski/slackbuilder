#!/bin/sh
#sed "s;^Slackware \([0-9][0-9]*\.[0-9][0-9]*\).*;\1;" /etc/slackware-version
egrep -o '[0-9]+\.[0-9]+' /etc/slackware-version
exit 0
