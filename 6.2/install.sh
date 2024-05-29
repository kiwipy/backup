#!/bin/bash
#
# File for:    backup (Github version)
# Copyright:   William Andersson 2024
# Website:     https://github.com/william-andersson
# License:     GPL
#
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

##### Script installation instructions #####
DEPENDENCIES=("bc rsync")
# Copy scripts
install -v -C -m 775 -o root backup.sh /usr/bin/toolbox-backup
# Copy configurations
if [ ! -f "/etc/toolbox-backup.cfg" ]; then
	install -v -C -m 666 -o root backup.cfg /etc/toolbox-backup.cfg
else
	echo "File /etc/toolbox-backup.cfg already exists, skipping..."
fi
if [ ! -f "/etc/systemd/system/toolbox-backup.timer" ]; then
	install -v -C -m 777 -o root backup.timer /etc/systemd/system/toolbox-backup.timer
else
	echo "File /etc/systemd/system/toolbox-backup.timer already exists, skipping..."
fi
if [ ! -f "/etc/systemd/system/toolbox-backup.service" ]; then
	install -v -C -m 777 -o root backup.service /etc/systemd/system/toolbox-backup.service
else
	echo "File /etc/systemd/system/toolbox-backup.service already exists, skipping..."
fi

if [ ! -z "$DEPENDENCIES" ];then
	/usr/bin/toolbox-depin ${DEPENDENCIES[@]}
fi

echo "Done."
