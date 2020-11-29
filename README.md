# Vertica PoC
This repository hosts code for quickly building out Vertica PoC environments for demos and tests. The focus is on Vertica Eon mode, with the S3 communal storage placed on Pure Storage FlashBlade.

-   The core of the work is done by Ansible from the Management Console instance/host. Ansible isn't necessary on the laptop or bastion host used to access the PoC environment (but may be helpful for setup and troubleshooting).
-   The playbooks and notes assume CentOS7 or Amazon Linux 2 for the hosts used to create and run the Vertica cluster.
-   Unless otherwise indicated, assume that commands here are run as the root user on the Management Console host. This doesn't reflect security best practices, so it's best for test labs and otherwise isolated networks.

# Setup Sequence
This sequence is for testing with AWS Outposts, but it would be very similar when running in other virtualized environments or bare metal.

## Create the Test Environment
For the PoC, we'll need **at least four instances or hosts**:
-   A relatively small instance (e.g., 4+ cores and 8+ GB) to act as the overall management jumpbox for the PoC and host the Vertica Management Console.
-   At least 3x instances that can be used as Vertica Eon cluster nodes. See [Vertica documentation][18fb251a] for recommended hardware and software specifications if this indented to test for eventual production deployment.

    [18fb251a]: https://www.vertica.com/kb/Recommendations-for-Sizing-Vertica-Nodes-and-Clusters/Content/Hardware/Recommendations-for-Sizing-Vertica-Nodes-and-Clusters.htm "Vertica Sizing Recommendations"

-   While not necessary, the PoC code in this repo is set up to support tests with isolated environments that use separate networks for (1) jumpbox/MC access, (2) isolated private network for the cluster nodes, (3) storage network with access to the FlashBlade hosting the S3 communal storage. The interfaces for each of these networks are defined in the setup script that's run first. If multiple functions are hosted on the same networks, simply list their interface in multiple places when customizing the setup script.


## On a Laptop or Bastion Host
This part should not be necessary for environments where root login to the hosts is already enabled. For AWS and Outposts, root
login is disabled on new instances. The following steps should re-enable it.

1.  Edit `/etc/hosts` and set the correct IP addresses for the management console (MC) and cluster node instances.
2.  Edit `~/.ssh/config` and set the user for the PoC hosts to be whatever the correct user is for those instances. (For Outposts/AWS, it's likely either `ec2-user` or `dbadmin` depending on AMI used.) Make sure a copy of the correct key is in `~/.ssh/` and referenced in the `~/.ssh/config` entry.
3.  Clone this repository onto your laptop or jumpbox, and modify the `outposts-openroot.sh` script.
```shell
   yum install -y git && git clone https://github.com/microslav/vertica-poc.git
   cd vertica-poc
   vim ./outposts-openroot.sh
```   
4.  Set the following variables to match your environment:  
```shell
   KEY="$HOME/.ssh/miroslav-pstg-outpost-keys.pem"  # Path to the private SSH key used to access the instances
   OS_USER="ec2-user"                               # OS/AMI user that can be accessed with the key
   MC_NAME="outposts-mc"                            # Name of the Management Console instance in /etc/hosts
   NODE_PREFIX="outposts-node"                      # Prefix for the cluster node instances in /etc/hosts
```
5.  When ready run the `.\outposts-openroot.sh` script to allow `root` login on the instances.
6.  Finally, edit `~/.ssh/config` and change the Outposts user to `root`. We'll be doing everything as root for this PoC. An example entry would look something like this:
```shell
Host outposts-*
  AddKeysToAgent yes
  HostName %h
  User root
  IdentityFile ~/.ssh/miroslav-pstg-outpost-keys.pem
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
```
7.  Gather the following files that you'll need and use `scp` to copy them into `/tmp/` on the MC:
```shell
  MY_MC="outposts-mc"
  scp vertica-10.xx.yy-zz.x86_64.RHEL6.rpm ${MY_MC}:/tmp/
  scp vertica-console-10.xx.yy-zz.x86_64.RHEL6.rpm ${MY_MC}:/tmp/
  scp rapidfile-xx-Linux.rpm ${MY_MC}:/tmp/ # optional RapidFile Toolkit to accelerate high file count operations from Pure
  scp tpcds_dist.tgz ${MY_MC}:/tmp/         # optional distributable for TPC-DS adapted for Vertica Eon mode and PoC
```

## On the Brand New MC Node
1.  Connect to the MC instance via `ssh`
2.  Make sure git is installed: `yum install -y git`
3.  Clone this repository onto the instance: `git clone https://github.com/microslav/vertica-poc.git`
4.  Copy the files to their proper destinations:
```shell
   cd vertica-poc
   cp /tmp/vertica-10.0.1-0.x86_64.RHEL6.rpm roles/vertica-node/files/
   cp /tmp/vertica-console-10.0.1-0.x86_64.RHEL6.rpm roles/mc/files/
   cp /tmp/rapidfile-1.0.0-beta.4-Linux.rpm roles/vertica-node/files/
   cp /tmp/tpcds_dist.tgz roles/primary-node/files/

```

## Edit the `vertica_poc_prep.sh` File
This is the main script that aims to automate all the PoC environment customization and sets up the MC instance to act as the central point of management for the PoC. You need to make edits to the various variables at the top of the script, and then source the script into your shell environment. The Ansible playbooks do the rest, and they need to look up some of the environment variables set during the script run.

### Edit General Settings
First, edit general settings for the overall environment:

-   **POC_ANSIBLE_GROUP**="vertica" – The Ansible Vertica nodes host group defined in the Ansible hosts file. Shouldn't need to be changed.
-   **POC_PREFIX**="outpost" – Short name for this PoC. It'll be used as a prefix for the internal DNS names for the hosts, although other fixed names are also assigned and used in the scripts.
-   **KEYNAME**="miroslav-pstg-outpost-keys" - Name of SSH key (without the suffix).
-   **LAB_DOM**="vertica.lab" - Internal domain created for PoC. This domain will be automatically set up within the PoC environment using `dnsmasq`.
-   **POC_DOM**="puretec.purestorage.com" - External domain where the PoC is set up. For AWS Outposts, use the domain of the local network where the Outpost is installed.
-   **POC_DNS**="123.123.123.123" - External DNS server IP address for the where PoC is set up. For AWS Outposts, use the primary DNS server for the local network where the Outpost is installed.
-   **POC_TZ**="America/Los_Angeles" – Local timezone where PoC runs. This will be set on all the hosts and reflected in the timestamps, logs, etc.

### Set the FlashBlade API Token
The Ansible playbook will configure the FlashBlade to be used for the PoC. It will create:

1.  NFS filesystem used for hosting test data before it's loaded into Vertica (`vertica`)
2.  S3 Account used for the PoC (`vertica`)
3.  S3 User within that account for the PoC (`dbadmin`)
4.  Access and Secret keys for that user
5.  S3 Bucket used for the PoC (`vertica`)

If any of the above defaults need to be changed, they are set within the `group_vars/all.yml` file inside the cloned playbook directory.

In order for the Ansible automation to access the FlashBlade, you need to set the `PUREFB_API` variable to an API token with sufficient permissions to perform those operations. You can obtain the API token by logging in to the FlashBlade via SSH, and then running one of the following commands:

-   `pureadmin create --api-token` if this is the first time setting up the API Token
-   `pureadmin list --api-token --expose` if the API Token already exists

Once you obtain a copy of the token, set instead of the placeholder in the PoC prep script:

-   **PUREFB_API**="T-deadbeef-f00d-cafe-feed-1337c0ffee"


### Set the PoC Platform Devices and Role Info
The following variables help customize the script for the PoC platform, hosts, and roles used during the PoC:

-   **VA_VIRTUAL_NODES**="True" - True if the hosts are virtual machines or instances, set to "False" for physical hosts (although won't hurt to keep it as "True" for smaller PoC environments). Used to configure the Spread network for Vertica.
-   **PRIV_NDEV**="eth0" - Private (primary) network interface. Most of the node communication will take place on this network during the PoC.
-   **PUBL_NDEV**="eth0" - Public network interface for management access to the MC instance. If this is different from the private network interface, it will be configured as a NAT gateway for the other nodes to use for access to the outside world (e.g., downloading new packages). This setup is for more secure PoC environments where only the MC is whitelisted for VPN access.
-   **DATA_NDEV**="eth0" - Data network interface for storage access. More common in production environments where the FlashBlade is on a separate storage network.
-   **EXTRAS_URI**="<https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm>" – URI for the package that enables access to Extras packages for the OS distribution used for the PoC. Sometimes different OS flavors have different syntax for enabling extra repositories. This should work across a range of flavors.
-   **VDB_DEPOT_SIZE**="512G" – Depot size per node. This should be about +2x host memory, but not more than
60-80% of the host's `/home` partion size. Minimum size is 32GB. You can use {K|M|G|T} suffix for size. For Outposts, there is a separate script that can be used to configure the ephemeral instance storage as the Depot location.
-   **OS_USERNAME**="ec2-user" – Name of non-root user for the OS (e.g., `dbadmin` for Vertica AMI, `ec2-user` for AWS Linux AMI). This is used to enable `root` access on the nodes in case it wasn't enabled from the laptop in an earlier step.
-   **DBUSER**="dbadmin" - Name of the Vertica database management user. Shouldn't need to be changed.
-   **LAB_IP_SUFFIX**="1" - The internal gateway IP address suffix on the private network. It's assigned to the MC host as a NAT gateway to the outside for other PoC hosts. If there is no separate private network, use the existing gateway suffix for the public network. Warning: this assumes a /24 network and the code might need to adjusted for wider networks.

### Set the IP Addresses for the Nodes and FlashBlade
The following section in the script is used to define the IP addresses for the environment:
```shell
read -r -d '' PRIMARY_HOST_ENTRIES <<-_EOF_
172.26.1.232 ${POC_PREFIX}-01 vertica-node001
172.26.1.32  ${POC_PREFIX}-02 vertica-node002
172.26.1.227 ${POC_PREFIX}-03 vertica-node003
_EOF_
read -r -d '' SECONDARY_HOST_ENTRIES <<-_EOF_
172.26.1.207 ${POC_PREFIX}-04 vertica-node004
172.26.1.208 ${POC_PREFIX}-05 vertica-node005
172.26.1.209 ${POC_PREFIX}-06 vertica-node006
_EOF_
read -r -d '' STORAGE_ENTRIES <<-_EOF_
10.21.239.11  ${POC_PREFIX}-fb-mgmt poc-fb-mgmt
10.21.241.148 ${POC_PREFIX}-fb-data poc-fb-data
_EOF_
```
Edit the IP addresses associated with the entries within the script. Some things to keep in mind:
-   You need to have at least 3 nodes defined in the Primary host section. Vertica needs at least three nodes for quorum. (Although a single node will work too for a non-redundant cluster.)
-   The license in `roles/primary-node/files/license.key` is for the free Community Edition, which is limited to three nodes and 1TB of data. If you have more than three Primary nodes or plan to test with more data, you'll need to change the license key to one that has higher limits.
-   The Secondary host section can be empty if you don't have any secondary hosts.
-   Any hosts in the Secondary section are configured as Standby nodes. These can be used to demonstrate things like cluster expansion, creating subclusters, etc.
-   You need to define both a Management and Data VIP on the FlashBlade that are accessible to the PoC environment and include the IP addresses here. You can also (optionally) list multiple accessible Data VIPs in the file using the same host names, and these will be served by the `dnsmasq` server via Round-Robin DNS during the PoC. Multiple Data VIPs are unlikely to result in performance gains during the PoC, but are a possible configuration option.
