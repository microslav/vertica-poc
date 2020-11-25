# Vertica PoC
This repository hosts code for quickly building out Vertica PoC environments for demos and tests. The focus is on Vertica Eon mode, with the S3 communal storage placed on Pure Storage FlashBlade.

- This playbook and notes assume CentOS7 or Amazon Linux 2 for the hosts used to create and run the Vertica cluster.
- Unless otherwise indicated, assume that commands here are run as the root user on the Management Console host.

# Random Notes

## Using AWS and Amazon Linux
1. Enable root access to the instances by copying the default user (ec2-user) ~/.ssh/authorized_keys to /root/.ssh/

## Brand New MC Node
1. Make sure git is installed: `yum install -y git`
2. Clone this repository onto the node: `git clone https://github.com/microslav/vertica-poc.git`

## Edit the `vertica_poc_prep.sh` File
