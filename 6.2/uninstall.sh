#!/bin/bash
#
# Uninstall backup version 6
#
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi
echo "*** Uninstalling backup v6 from system ***"
systemctl disable toolbox-backup.timer --now
rm -v /usr/bin/toolbox-backup
rm -v /etc/toolbox-backup.cfg
rm -v /etc/systemd/system/toolbox-backup.timer
rm -v /etc/systemd/system/toolbox-backup.service
systemctl daemon-reload
echo "Done."
