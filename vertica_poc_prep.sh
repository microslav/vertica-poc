#!/usr/bin/env bash

if [[ "$(basename -- "$0")" == "vertica_poc_prep.sh" ]]; then
    echo "Don't run $0, source it in a console window" >&2
    exit 1
fi

# set -x

######################################################################
###
### Script to set up a Vertica PoC Command Host for a PoC
###
### Assumptions:
###   1. Script is run as root
###   2. Network device names are identical across all nodes
###
######################################################################

######################################################################
### MODIFY VARIABLES BELOW TO ALIGN WITH LOCAL POC SETTINGS
######################################################################

### PoC General Settings
export POC_ANSIBLE_GROUP="vertica"              # Ansible Vertica nodes host group
export POC_PREFIX="outpost"                     # Short name for this POC
export KEYNAME="miroslav-pstg-outpost-keys"     # Name of SSH key (without suffix)
export LAB_DOM="vertica.lab"                    # Internal domain created for PoC
export POC_DOM="puretec.purestorage.com"        # External domain where PoC runs
export POC_DNS="10.21.93.16"                    # External DNS IP where PoC runs
export POC_TZ="America/Los_Angeles"             # Timezone where PoC runs

### FlashBlade API Token (get via SSH to FlashBlade CLI; see Admin docs)
export PUREFB_API="T-deadbeef-f00d-cafe-feed-1337c0ffee"

### PoC Platform Devices and Roles
# True if the hosts are virtual machines or instances, False for physical hosts
export VA_VIRTUAL_NODES="True"
# If collapsing multiple networks (e.g., public and private, private and storage),
# repeat the name of the device in multiple places:
export PRIV_NDEV="eth0"      # Private (primary) network interface
export PUBL_NDEV="eth0"      # Public network interface for access and NAT
export DATA_NDEV="eth0"      # Data network interface for storage access
# URL for the extras repository matching host OS distributions
export EXTRAS_URI="https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
# Depot size per node. This should be about 2x host memory, but not more than
# 60-80% of the host's /home partion size. Use {K|M|G|T} suffix for size.
export VDB_DEPOT_SIZE="512G"
# Name of non-root user for the OS (e.g., dbadmin for Vertica AMI, ec2-user for AWS Linux AMI)
export OS_USERNAME="ec2-user"
# Name of Vertica database user (shouldn't need to be changed)
export DBUSER="dbadmin"

### Internal gateway IP address suffix on private network. It's assigned to
### the Command host as a NAT gateway to the outside for other PoC hosts.
### If there is no separate private network, use the gateway suffix for the
### public network.
### (!!! Assumes a /24 network; might need to fix for others !!!).
export LAB_IP_SUFFIX="1"

### Set IP addresses for the Vertica nodes and FlashBlade
read -r -d '' PRIMARY_HOST_ENTRIES <<-_EOF_
172.26.1.101 ${POC_PREFIX}-01 vertica-node001
172.26.1.102 ${POC_PREFIX}-02 vertica-node002
172.26.1.103 ${POC_PREFIX}-03 vertica-node003
_EOF_
read -r -d '' SECONDARY_HOST_ENTRIES <<-_EOF_
172.26.1.201 ${POC_PREFIX}-04 vertica-node004
172.26.1.202 ${POC_PREFIX}-05 vertica-node005
172.26.1.203 ${POC_PREFIX}-06 vertica-node006
_EOF_
read -r -d '' STORAGE_ENTRIES <<-_EOF_
10.99.100.100  ${POC_PREFIX}-fb-mgmt poc-fb-mgmt
10.99.101.100 ${POC_PREFIX}-fb-data poc-fb-data
_EOF_

### Configure how and what to run in the playbook
export VA_SEL_REBOOT="yes"
export VA_RUN_VPERF="yes"
export VA_RUN_VMART="yes"
export VA_PAUSE_CHECK="yes"

######################################################################
### CODE BELOW SHOULD NOT NEED TO BE MODIFIED
######################################################################

### Platform
export IS_AWS_UUID="$(sudo dmidecode --string=system-uuid | cut -c1-3)"
export PRETTY_NAME="$(grep PRETTY_NAME= /etc/os-release | cut -d\" -f2)"
export AZL2_NAME="Amazon Linux 2"

### Helper Functions:
# dev_ip() -- Return the first IP address associated with an interface
# dev_cidr() -- Return the CIDR associated with an interface
# dev_conn() -- Return the connection name associated with an interface
if [ "$PRETTY_NAME" == "$AZL2_NAME" ]; then
    function dev_ip()   { local myIP=$(ip addr show dev $1 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1); echo "$myIP"; }
    function dev_cidr() { local myCIDR=$(ip addr show dev $1 | grep 'inet ' | awk '{print $2}'); echo "$myCIDR"; }
    function dev_conn() { local myCONN=$1; echo "$myCONN"; }
else
    function dev_ip()   { local myIP=$(nmcli dev show $1 | grep -F 'IP4.ADDRESS[1]:' | awk '{print $NF}' | cut -d/ -f1); echo "$myIP"; }
    function dev_cidr() { local myCIDR=$(nmcli dev show $1 | grep -F 'IP4.ADDRESS[1]:' | awk '{print $NF}'); echo "$myCIDR"; }
    function dev_conn() { local myCONN=$(nmcli dev show $1 | grep -F 'GENERAL.CONNECTION:' | awk '{print $NF}'); echo "$myCONN"; }
fi

### Network Connection information
export PRIV_IP=$(dev_ip "$PRIV_NDEV")
export PUBL_IP=$(dev_ip "$PUBL_NDEV")
export DATA_IP=$(dev_ip "$DATA_NDEV")
export PRIV_CIDR=$(dev_cidr "$PRIV_NDEV")
export PUBL_CIDR=$(dev_cidr "$PUBL_NDEV")
export DATA_CIDR=$(dev_cidr "$DATA_NDEV")
export PRIV_CONN=$(dev_conn "$PRIV_NDEV")
export PUBL_CONN=$(dev_conn "$PUBL_NDEV")
export DATA_CONN=$(dev_conn "$DATA_NDEV")
export PRIV_PREFIX=$(echo $PRIV_CIDR | cut -d/ -f2)

### Initial packages to install before Ansible configured
export PYPKG="gcc openssl-devel bzip2-devel libffi-devel zlib-devel python3 python3-devel libselinux-python3"
export DNSPKG="dnsmasq bind-utils ntp"

### For dnsmasq setup
export HOSTNAME_ORIG=$(hostname)
export HOSTNAME_C3="${POC_PREFIX}-command"
export LAB_PRIV_NET=$(echo "$PRIV_IP" | cut -d. -f1-3)
export LAB_PUBL_NET=$(echo "$PUBL_IP" | cut -d. -f1-3)
export LAB_DATA_NET=$(echo "$DATA_IP" | cut -d. -f1-3)
export LAB_RDNS_PUBL="$(echo $LAB_PUBL_NET | awk -F. '{print $3 "." $2 "." $1}').in-addr.arpa"
export LAB_RDNS_PRIV="$(echo $LAB_PRIV_NET | awk -F. '{print $3 "." $2 "." $1}').in-addr.arpa"
export LAB_RDNS_DATA="$(echo $LAB_DATA_NET | awk -F. '{print $3 "." $2 "." $1}').in-addr.arpa"
export LAB_DNS_IP="${PRIV_IP}"
export LAB_GW="${LAB_PRIV_NET}.${LAB_IP_SUFFIX}"

### Install some basic packages
if [ "$PRETTY_NAME" == "$AZL2_NAME" ]; then
    # AZ Linux 2 doesn't have firewalld or NetworkManager/nmcli
    yum install -y ${EXTRAS_URI}
    alias dnf=yum
    yum install -y deltarpm nvme-cli
    yum install -y firewalld && systemctl start firewalld && systemctl enable firewalld
else
    yum install -y epel-release
    yum install -y dnf deltarpm
fi

### Install or update python3 and related packages
dnf install -y ${PYPKG}

### Set up virtual environment with Python3 and recent Ansible
export VENV="pocenv"
python3 -m ensurepip
python3 -m pip install virtualenv
python3 -m virtualenv ${PWD}/${VENV}
pip3 install --upgrade selinux  # Also needed outside venv on AWS for some reason
source ${PWD}/${VENV}/bin/activate
pip3 install --upgrade ansible selinux

### Set up SSH keys for login and Ansible
export PUBPATH="${HOME}/.ssh/${KEYNAME}.pub"
if [ "${IS_AWS_UUID^^}" == "EC2" ]; then
    # If AWS, then check that the key(s) have been uploaded and given expected name(s)
    export KEYPATH="${HOME}/.ssh/${KEYNAME}.pem"
    [[ -f "${KEYPATH}" ]] || { echo "!!! ERROR: Please upload the private SSH key to ${KEYPATH} !!!"; return 1; }
    [[ -f "${PUBPATH}" ]] || ssh-keygen -y -f ${KEYPATH} > ${PUBPATH}
    [[ -L "${HOME}/.ssh/vertica-poc" ]] || ln -s ${KEYPATH} ${HOME}/.ssh/vertica-poc
else
    # If not AWS, create a set of keys to use to access Vertica hosts
    export KEYPATH="${HOME}/.ssh/${KEYNAME}"
    [[ -d "${HOME}/.ssh" ]] || mkdir -m 700 ${HOME}/.ssh
    [[ -f "${KEYPATH}" ]] || ssh-keygen -f ${KEYPATH} -q -N ""
    chmod 600 $KEYPATH
    [[ -L "${HOME}/.ssh/vertica-poc" ]] || ln -s ${KEYPATH} ${HOME}/.ssh/vertica-poc
fi
[[ -L "${HOME}/.ssh/vertica-poc.pub" ]] || ln -s ${PUBPATH} ${HOME}/.ssh/vertica-poc.pub

### Create SSH config using standardized "vertica-poc" link names
[[ -f "${HOME}/.ssh/config" ]] && mv ${HOME}/.ssh/config ${HOME}/.ssh/config_ORIG
cat <<_EOF_ > ${HOME}/.ssh/config
Host vertica-* ${POC_PREFIX}-* ${LAB_PRIV_NET}.* command
   HostName %h
   User root
   IdentityFile ${HOME}/.ssh/vertica-poc
   StrictHostKeyChecking no
   LogLevel ERROR
   UserKnownHostsFile=/dev/null

_EOF_

######################################################################
### If using a separate private interface, set up NAT on the Command
### host and configure the private interface as a gateway.
######################################################################

# We need firewalld for the NAT
systemctl start firewalld
systemctl enable firewalld
firewall-cmd --state

# Only set up NAT if separate private interfaces
if [ "${PRIV_NDEV}" != "${PUBL_NDEV}" ]; then
    echo "Setting up NAT on the Private Interface"
    # Add gateway address to the private interface
    nmcli connection modify ${PRIV_CONN} +ipv4.addresses "${LAB_GW}/${PRIV_PREFIX}"
    # Set up IP forwarding in the kernel for NAT (if not already set up)
    if [[ $(grep -Fqs 'net.ipv4.ip_forward = 1' /etc/sysctl.d/ip_forward.conf) != 0 ]]; then
	     echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.d/ip_forward.conf
	     sysctl -p /etc/sysctl.d/ip_forward.conf
    fi
    # Set up NAT and configure zones
    firewall-cmd --permanent --direct --passthrough ipv4 -t nat -I POSTROUTING -o ${PUBL_NDEV} -j MASQUERADE -s ${PRIV_CIDR}
    firewall-cmd --permanent --change-interface=${PRIV_NDEV} --zone=trusted
fi

# Add allowed services and ports for the public zone
firewall-cmd --permanent --change-interface=${PUBL_NDEV} --zone=public
firewall-cmd --permanent --change-interface=${DATA_NDEV} --zone=public
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --permanent --zone=public --add-service=https
firewall-cmd --permanent --zone=public --add-service=dns
firewall-cmd --permanent --zone=public --add-service=dhcp
firewall-cmd --permanent --zone=public --add-service=dhcpv6-client
firewall-cmd --permanent --zone=public --add-service=mosh
firewall-cmd --permanent --zone=public --add-service=ssh
firewall-cmd --permanent --zone=public --add-service=ntp
firewall-cmd --permanent --zone=public --add-service=vnc-server
firewall-cmd --permanent --zone=public --add-port=5450/tcp

# Reload and restart everything
firewall-cmd --complete-reload
systemctl restart network && systemctl restart firewalld

######################################################################
### Set up DNS services
######################################################################

# Install dnsmasq and bind-utils (or equivalent)
dnf install -y $DNSPKG

# Save original files just in case
TS="$(printf '%(%Y-%m-%d_%H-%M-%S)T.bkup' -1)"
cp /etc/dnsmasq.conf /etc/dnsmasq_${TS}
cp /etc/hosts /etc/hosts_${TS}
cp /etc/ansible/hosts /etc/ansible/hosts_${TS}
cp /etc/ansible/ansible.cfg /etc/ansible/ansible.cfg_${TS}

# Generate new dnsmasq config file:
cat <<_EOF_  > /etc/dnsmasq.conf
domain-needed
bogus-priv
no-resolv
no-poll
server=/${LAB_DOM}/127.0.0.1
server=/${POC_DOM}/${POC_DNS}
server=8.8.8.8
server=8.8.4.4
server=/${LAB_RDNS_PUBL}/127.0.0.1
server=/${LAB_RDNS_PRIV}/127.0.0.1
server=/${LAB_RDNS_DATA}/127.0.0.1
local=/${LAB_DOM}/
expand-hosts
domain=${LAB_DOM}
_EOF_

# Generate new /etc/hosts file for dnsmasq
cat <<_EOF_ > /etc/hosts
# Local machine names
${LAB_GW}  ${POC_PREFIX}-gw
${PRIV_IP} ${HOSTNAME_C3} command mc ns1 www
${PUBL_IP} ${HOSTNAME_ORIG} vertica-jumpbox ${HOSTNAME_C3}-publ command-publ mc-publ

# PoC hosts
$PRIMARY_HOST_ENTRIES
$SECONDARY_HOST_ENTRIES

# Storage
$STORAGE_ENTRIES

# Localhost
127.0.0.1    localhost localhost4
::1          localhost localhost6
_EOF_

### Test config file syntax, allow in firewall and start the service
dnsmasq --test
systemctl start dnsmasq
systemctl enable dnsmasq
systemctl status dnsmasq

### Make dnsmasq a system daemon that automatically restarts
cat <<_EOF_ > /etc/systemd/system/dnsmasq.service
[Unit]
Description=DNS caching server.
After=network.target
[Service]
ExecStart=/usr/sbin/dnsmasq -k
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
_EOF_

### Restart and check
systemctl daemon-reload
systemctl restart dnsmasq
systemctl status dnsmasq

### Use this (Command) server to resolve names
cat <<_EOF_ > /tmp/ifcfg_delta
DOMAIN=${LAB_DOM}
DNS1=${LAB_DNS_IP}
_EOF_
if [ "${PRETTY_NAME}" == "${AZL2_NAME}" ]; then
    # Amazon Linux doesn't use NetworkManager and nmcli
    cat /tmp/ifcfg_delta >> /etc/sysconfig/network-scripts/ifcfg-${PRIV_NDEV}
    cp /etc/resolv.conf /etc/resolv.ORIG
    systemctl restart network
else
    if [ "${PRIV_CONN}" != "${PUBL_NDEV}" ]; then
	      nmcli connection modify ${PRIV_CONN} ipv4.ignore-auto-dns yes
	      nmcli connection modify ${PRIV_CONN} ipv4.dns ${LAB_DNS_IP}
	      nmcli connection modify ${PRIV_CONN} ipv4.dns-search ${LAB_DOM}
	      nohup bash -c "nmcli connection down ${PRIV_CONN} && nmcli connection up ${PRIV_CONN}"
	      sleep 1
    fi
    nmcli connection modify ${PUBL_CONN} ipv4.ignore-auto-dns yes
    nmcli connection modify ${PUBL_CONN} ipv4.dns ${LAB_DNS_IP}
    nmcli connection modify ${PUBL_CONN} ipv4.dns-search ${LAB_DOM}
    nohup bash -c "nmcli connection down ${PUBL_CONN} && nmcli connection up ${PUBL_CONN}"
    sleep 1
fi

### Change hostname to match /etc/hosts
[[ "$(hostname)" == "${HOSTNAME_C3}" ]] || hostnamectl set-hostname ${HOSTNAME_C3}

### Install Ansible package and then FlashBlade collection
ansible-galaxy collection install purestorage.flashblade

### Define Ansible hosts file (and save original!)
PNODES="$(echo "${PRIMARY_HOST_ENTRIES}" | awk '{print $NF}')"
SNODES="$(echo "${SECONDARY_HOST_ENTRIES}" | awk '{print $NF}')"
cat <<_EOF_ > ./hosts.ini
[mc]
command

[primary_nodes]
$PNODES

[secondary_nodes]
$SNODES

[vertica_nodes:children]
primary_nodes
secondary_nodes

[${POC_ANSIBLE_GROUP}:children]
mc
vertica_nodes

[${POC_ANSIBLE_GROUP}:vars]
ansible_shell_executable=/bin/bash
ansible_user=root
ansible_ssh_private_key_file=${HOME}/.ssh/vertica-poc
_EOF_

### Create local Ansible config file and use local inventory file
cat <<_EOF_ > ./ansible.cfg
[defaults]
inventory = ${PWD}/hosts.ini
forks = 32
executable = /bin/bash
host_key_checking = False
deprecation_warnings = False
interpreter_python = auto_silent
callback_enabled = timer, profile_tasks

### Enable task timing info
[callback_profile_tasks]
task_output_limit = 500
sort_order = none
_EOF_

### Set up or fix SSH keys for root access
NODES="$(grep -E 'vertica-node|ns1' /etc/hosts | awk '{print $3}')"
echo "====== Set up SSH authentication for PoC hosts ======"
echo "(say 'yes' if prompted and enter password repeatedly)"
for node in ${NODES}
do
    if [ ${IS_AWS_UUID^^} == "EC2" ]; then
	      ssh -i $KEYPATH ${OS_USERNAME}@${node} "sudo cp /home/${OS_USERNAME}/.ssh/authorized_keys /root/.ssh/authorized_keys"
    else
	      ssh-copy-id -i $KEYPATH root@${node}
    fi
done

### Make sure Ansible is working
ansible all -o -m ping

### Install packages we'll need on the PoC
# Install packages we'll need later
ansible vertica_nodes -m package -a 'name=bind-utils,ntp,traceroute,firewalld,python3 state=latest'

### Configure PoC hosts
# Rename the hosts to match /etc/hosts and Ansible inventory
ansible vertica_nodes -o -m hostname -a "name={{ inventory_hostname_short }}"
# Make sure NetworkManager and firewalld are running and enabled
ansible vertica_nodes -m systemd -a 'name=firewalld state=started enabled=yes masked=no'

# Add dnsmasq DNS to the private interface (and public interface if they're the same)
if [ "${PRETTY_NAME}" == "${AZL2_NAME}" ]; then
    # Amazon Linux doesn't use NetworkManager and nmcli
    ansible vertica_nodes -o -m copy  -a "src=/tmp/ifcfg_delta dest=/tmp/ifcfg_delta"
    ansible vertica_nodes -o -m shell -a "cat /tmp/ifcfg_delta >> /etc/sysconfig/network-scripts/ifcfg-${PRIV_NDEV}"
    ansible vertica_nodes -o -m shell -a "cp /etc/resolv.conf /etc/resolv.ORIG"
else
    ansible vertica_nodes -m package -a 'name=NetworkManager state=latest'
    ansible vertica_nodes -m systemd -a 'name=NetworkManager state=started enabled=yes masked=no'
    ansible vertica_nodes -o -m nmcli \
	    -a "type=ethernet conn_name=${PRIV_NDEV} gw4=${LAB_GW} dns4=${LAB_DNS_IP} dns4_search=${LAB_DOM} state=present"
fi
# Network changes if private and public interfaces are separate devices
if [ "${PRIV_NDEV}" != "${PUBL_NDEV}" ]; then
    # Set the private interface to be on the trusted zone for the firewall
    ansible vertica_nodes -m ansible.posix.firewalld \
	   -a "interface=${PRIV_NDEV} zone=trusted permanent=true state=enabled immediate=yes"
    ansible vertica_nodes -m shell \
	   -a "nmcli connection modify ${PRIV_NDEV} connection.zone trusted"
    # Remove any DNS servers on the public interfaces and use only the private interface
    ansible vertica_nodes -o -m nmcli -a "type=ethernet conn_name=${PUBL_NDEV} dns4='' dns4_search='' state=present"
fi
# Restart the networking and firewall
ansible vertica_nodes -m service -a "name=network state=restarted"
ansible vertica_nodes -m service -a "name=firewalld state=restarted"

### Test that dnsmasq DNS is working from the PoC hosts
ansible vertica_nodes -o -m shell -a "sed -i 's|^hosts:\s*.*$|hosts:      dns files myhostname|g' /etc/nsswitch.conf"
ansible vertica_nodes -o -m shell -a 'dig command google.com +short'
ansible vertica_nodes -o -m shell -a "dig -x ${LAB_DNS_IP} +short"

### Set up NTP and synchronize time on all hosts
cat <<_EOF_ > /tmp/ntp.conf
driftfile /var/lib/ntp/drift
restrict default
server ${PRIV_IP} iburst
disable monitor
_EOF_
ansible all -o -m shell -a 'timedatectl set-ntp true'
ansible all -o -m shell -a "timedatectl set-timezone ${POC_TZ}"
ansible all -m service -a "name=ntpd state=stopped"
if [ "${PRIV_NDEV}" != "${PUBL_NDEV}" ]; then
    ansible vertica_nodes -o -m copy  -a "src=/tmp/ntp.conf dest=/etc/ntp.conf"
fi
ansible all -o -m shell -a 'ntpd -gq'
ansible all -m service -a "name=ntpd state=started"
sleep 10
ansible all -m shell -a 'ntpstat'
ansible all -m shell -a 'timedatectl status | grep "NTP synchronized:"'
ansible all -m shell -a 'date'

# set +x
