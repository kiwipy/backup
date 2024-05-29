#!/bin/bash
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi
echo "*** Uninstalling bakup from system ***"
systemctl disable bakup-auto.timer --now
rm -v /usr/local/bin/bakup
rm -v /etc/systemd/system/bakup-auto.service
rm -v /etc/systemd/system/bakup-auto.timer
rm -v /usr/local/etc/bakup.cfg
rm -rv /usr/local/share/bakup
systemctl daemon-reload
echo "Done."
