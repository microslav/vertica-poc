#!/usr/bin/env bash

DBUSER="dbadmin"
DBGRP="verticadba"
ISTO_DEV="$(nvme list | grep 'Instance Storage' | awk '{print $1}')"
MPATH="/home/${DBUSER}/depot/"

### Create a script that will format and mount the ephemeral instance storage
cat <<_EOF_ > /usr/local/sbin/use-ephemeral.sh
# Format the device
mkfs.xfs -E nodiscard $ISTO_DEV
# Prep and mount the filesystem
mkdir -p $MPATH
mount -o discard $ISTO_DEV $MPATH
chown ${DBUSER}:${DBGRP} $MPATH
_EOF_
chmod +x /usr/local/sbin/use-ephemeral.sh

### Create a systemd startup script that will call the instance storage prep script
cat <<_EOF_ > /etc/systemd/system/instance-storage.service
[Unit]
Description=Prepare and Use Ephemeral Instance Storage on Boot
Wants=network-online.target
After=network-online.target
Before=remote-fs.target
[Service]
ExecStart=/usr/local/sbin/use-ephemeral.sh
[Install]
WantedBy=default.target
_EOF_

### Restart and check
systemctl daemon-reload
systemctl restart instance-storage
systemctl status instance-storage
df -h $MPATH
