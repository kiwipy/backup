#!/bin/bash
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi
echo "*** Installing bakup $(grep 'VERSION=' bakup.sh | sed 's/^.*=//') ***"

# Program files (always install)
install -C -D -m 755 -v bakup.sh /usr/local/bin/bakup
install -C -D -m 755 -v bakup-auto.service /etc/systemd/system/bakup-auto.service

# Config files (install if not exist)
if [ ! -f "/etc/systemd/system/bakup-auto.timer" ];then
    install -C -D -m 755 -v bakup-auto.timer /etc/systemd/system/bakup-auto.timer
fi
if [ ! -f "/usr/local/share/bakup/exclude" ];then
    install -C -D -m 644 -v exclude /usr/local/share/bakup/exclude
fi

systemctl daemon-reload
echo "Done."
