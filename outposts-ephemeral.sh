#!/usr/bin/env bash

############################################################
# Script for using the ephemeral instance storage as Depot
#
# If using instances with ephemeral devices, pause the
# playbook after the *common* role completes. Then manually:
#   ansible vertica_nodes -m copy -a 'src=./outposts-ephemeral.sh dest=/tmp/ mode=0744'
#   ansible vertica_nodes -m shell -a '/tmp/outposts-ephemeral.sh'
#   ansible vertica_nodes -m shell -a 'df -h /home/dbadmin/depot/'
############################################################

DBUSER="dbadmin"
DBGRP="verticadba"
ISTO_DEV="$(nvme list | grep 'Instance Storage' | awk '{print $1}')"
MPATH="/home/${DBUSER}/depot/"

### Create a script that will format and mount the ephemeral instance storage
cat <<_EOF_ > /usr/local/sbin/use-ephemeral.sh
#!/bin/bash
# Format the device
mkfs.xfs -f -K $ISTO_DEV
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
systemctl enable instance-storage
systemctl status instance-storage
sleep 3
df -h $MPATH
