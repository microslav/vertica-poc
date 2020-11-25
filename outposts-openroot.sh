#!/usr/bin/env bash

NODES="outposts-mc $(grep outposts-node /etc/hosts | awk '{print $2}')"
KEY="~/.ssh/miroslav-pstg-outpost-keys.pem"
OSUSER="ec2-user"

for host in $NODES
do
    ssh -i $KEY ${OSUSER}@${host} "sudo cp ~/.ssh/authorized_keys /root/.ssh/authorized_keys"
    echo "Overwrote root authorized_keys on ${host}"
    ssh -i $KEY ${OSUSER}@${host} "sudo hostnamectl set-hostname ${host}"
    echo "Changed the hostname to be ${host}"
done

 
