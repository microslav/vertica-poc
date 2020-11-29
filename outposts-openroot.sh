#!/usr/bin/env bash

KEY="$HOME/.ssh/miroslav-pstg-outpost-keys.pem"
OS_USER="ec2-user"
MC_NAME="outposts-mc"
NODE_PREFIX="outposts-node"
NODES="${MC_NAME} $(grep ${NODE_PREFIX} /etc/hosts | awk '{print $2}')"

for host in $NODES
do
    ssh -i $KEY ${OS_USER}@${host} "sudo cp ~/.ssh/authorized_keys /root/.ssh/authorized_keys"
    echo "Overwrote root authorized_keys on ${host}"
    ssh -i $KEY ${OS_USER}@${host} "sudo hostnamectl set-hostname ${host}"
    echo "Changed the hostname to be ${host}"
done
