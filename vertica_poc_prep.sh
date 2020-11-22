if [[ "$(basename -- "$0")" == "vertica_poc_prep.sh" ]]; then
    echo "Don't run $0, source it in a console window" >&2
    exit 1
fi

set -x 

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
export POC_PREFIX="fsa"                         # Short name for this POC
export KEYNAME="fsa-vertica-keys"               # Name of SSH key (without suffix)
export LAB_DOM="vertica.lab"                    # Internal domain created for PoC
export POC_DOM="fsa.lab"                        # External domain where PoC runs
export POC_DNS="10.21.234.10"                   # External DNS IP where PoC runs
export POC_TZ="America/Los_Angeles"             # Timezone where PoC runs

### FlashBlade API Token (get via SSH to FlashBlade CLI; see Admin docs)
export PUREFB_API="T-11111111-2222-3333-4444-555555555555"   # <== CHANGE ME

### PoC Platform Devices and Roles
# True is the hosts are virtual machines or instances, False for physical hosts
export VA_VIRTUAL_NODES="True"
# If collapsing multiple networks (e.g., public and private, private and storage),
# repeat the name of the device in multiple places:
export PRIV_NDEV="ens192"      # Private (primary) network interface
export PUBL_NDEV="ens224"      # Public network interface for access and NAT
export DATA_NDEV="ens224"      # Data network interface for storage access
# URL for the extras repository matching host OS distributions
export EXTRAS_URI="https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
# Depot size per node. This should be about 2x host memory, but not more than
# 60-80% of the host's /home partion size. Use {K|M|G|T} suffix for size.
export VDB_DEPOT_SIZE="32G"

### Internal gateway IP address suffix on private network. It's assigned to
### the Command host as a NAT gateway to the outside for other PoC hosts.
### If there is no separate private network, use the gateway suffix for the
### public network. 
### (!!! Assumes a /24 network; might need to fix for others !!!).
export LAB_IP_SUFFIX="1"

### Set IP addresses for the Vertica nodes and FlashBlade
read -r -d '' PRIMARY_HOST_ENTRIES <<-_EOF_
192.168.1.3 ${POC_PREFIX}-01 vertica-node001
192.168.1.4 ${POC_PREFIX}-02 vertica-node002
192.168.1.5 ${POC_PREFIX}-03 vertica-node003
_EOF_
read -r -d '' SECONDARY_HOST_ENTRIES <<-_EOF_
192.168.1.6 ${POC_PREFIX}-04 vertica-node004
192.168.1.7 ${POC_PREFIX}-05 vertica-node005
192.168.1.8 ${POC_PREFIX}-06 vertica-node006
_EOF_
read -r -d '' STORAGE_ENTRIES <<-_EOF_
10.21.200.5 ${POC_PREFIX}-fb-mgmt poc-fb-mgmt
10.21.200.4 ${POC_PREFIX}-fb-data poc-fb-data
_EOF_

### Configure how and what to run in the playbook
export VA_RUN_VPERF="true"
export VA_RUN_VMART="true"
export VA_PAUSE_CHECK="true
"
######################################################################
### CODE BELOW SHOULD NOT NEED TO BE MODIFIED
######################################################################

### Helper Functions
# Return the first IP address associated with an interface
function dev_ip() 
{ 
    local myIP=$(nmcli dev show $1 | grep -F 'IP4.ADDRESS[1]:' | awk '{print $NF}' | cut -d/ -f1)
    echo "$myIP"
}

# Return the CIDR associated with an interface
function dev_cidr() 
{ 
    local myCIDR=$(nmcli dev show $1 | grep -F 'IP4.ADDRESS[1]:' | awk '{print $NF}')
    echo "$myCIDR"
}

# Return the connection name associated with an interface
function dev_conn() 
{ 
    local myCONN=$(nmcli dev show $1 | grep -F 'GENERAL.CONNECTION:' | awk '{print $NF}')
    echo "$myCONN"
}

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

### Platform
export IS_AWS_UUID="$(sudo dmidecode --string=system-uuid | cut -c1-3)"

### Initial packages to install before Ansible configured
export INITPKG="python-pip ansible"
export DNSPKG="dnsmasq bind-utils"

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

# Name of Vertica non-root user (Should not be changed, but parameterized for testing)
export DBUSER="dbadmin"                         

### Install some basic packages
yum install -y epel-release
yum install -y dnf deltarpm
dnf install -y $INITPKG

### Use pip to install Ansible to get newer version than EPEL
pip install --upgrade pip
pip install --upgrade wheel
pip uninstall -y ansible        # Need EPEL version first to set up system files
pip install --upgrade ansible

### Set up SSH keys for login and Ansible
export PUBPATH="${HOME}/.ssh/${KEYNAME}.pub"
if [ ${IS_AWS_UUID^^} == "EC2" ]; then
    # If AWS, then check that the key(s) have been uploaded and given expected name(s)
    export KEYPATH="${HOME}/.ssh/${KEYNAME}.pem"
    [[ -f "${KEYPATH}" ]] || { echo "!!! ERROR: Please upload the private SSH key to ${KEYPATH} !!!"; exit 1; }
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
   User root
   IdentityFile ${HOME}/.ssh/vertica-poc
   StrictHostKeyChecking no
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
if [ "${PRIV_CONN}" != "${PUBL_NDEV}" ]; then
    # Add gateway address to the private interface
    nmcli connection modify ${PRIV_CONN} +ipv4.addresses "${LAB_GW}/${PRIV_PREFIX}"
    # Set up IP forwarding in the kernel for NAT (if not already set up)
    if [ $(grep -Fq 'net.ipv4.ip_forward = 1' /etc/sysctl.d/ip_forward.conf) != 0 ]]; then
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
cp /etc/dnsmasq.conf /etc/dnsmasq_$(printf '%(%Y-%m-%d_%H-%M-%S)T.bkup' -1)
cp /etc/hosts /etc/hosts_$(printf '%(%Y-%m-%d_%H-%M-%S)T.bkup' -1)
cp /etc/ansible/hosts /etc/ansible/hosts_$(printf '%(%Y-%m-%d_%H-%M-%S)T.bkup' -1)
cp /etc/ansible/ansible.cfg /etc/ansible/ansible.cfg_$(printf '%(%Y-%m-%d_%H-%M-%S)T.bkup' -1)

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
ansible_user=root
ansible_ssh_private_key_file=${HOME}/.ssh/vertica-poc
_EOF_
cat ./hosts.ini >> /etc/ansible/hosts

### Modify Ansible config for convenience
sed -i 's|^#forks\s*=\s*5|forks = 32\ninterpreter_python = auto_legacy_silent|g' /etc/ansible/ansible.cfg
sed -i 's|^#executable\s*=\s*/bin/sh|executable = /bin/bash|g' /etc/ansible/ansible.cfg
sed -i 's|^#callback_whitelist\s*=\s*.*$|callback_whitelist = timer, profile_tasks|g' /etc/ansible/ansible.cfg
cat <<_EOF_ >> /etc/ansible/ansible.cfg

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
	ssh -i $KEYPATH ${DBUSER}@${node} sudo cp /home/${DBUSER}/.ssh/authorized_keys /root/.ssh/authorized_keys
    else
	ssh-copy-id -i $KEYPATH root@${node}
    fi
done

### Make sure Ansible is working
ansible all -o -m ping

### Configure PoC hosts
# Rename the hosts to match /etc/hosts and Ansible inventory
ansible vertica_nodes -o -m hostname -a "name={{ inventory_hostname_short }}"
# Remove any DNS servers on the public interfaces and use only the private interface
ansible vertica_nodes -o -m nmcli -a "type=ethernet conn_name=${PUBL_NDEV} dns4='' dns4_search='' state=present"
# Add dnsmasq DNS to the private interface (and public interface if they're the same)
ansible vertica_nodes -o -m nmcli \
    -a "type=ethernet conn_name=${PRIV_NDEV} gw4=${LAB_GW} dns4=${LAB_DNS_IP} dns4_search=${LAB_DOM} state=present"
# Set the private interface to be on the trusted zone for the firewall (if it is a separate device)
if [ "${PRIV_NDEV}" != "${PUBL_NDEV}" ]; then
    ansible vertica_nodes -m ansible.posix.firewalld \
	-a "interface=${PRIV_NDEV} zone=trusted permanent=true state=enabled immediate=yes"
    ansible vertica_nodes -m shell \
	-a "nmcli connection modify ${PRIV_NDEV} connection.zone trusted"
fi
# Restart the networking and firewall
ansible vertica_nodes -m service -a "name=network state=restarted"
ansible vertica_nodes -m service -a "name=firewalld state=restarted"

### Test that dnsmasq DNS is working from the PoC hosts
ansible vertica_nodes -m package -a 'name=bind-utils state=present'
ansible vertica_nodes -o -m shell -a "sed -i 's|^hosts:\s*.*$|hosts:      dns files myhostname|g' /etc/nsswitch.conf"
ansible vertica_nodes -o -m shell -a 'dig command google.com +short'
ansible vertica_nodes -o -m shell -a "dig -x ${LAB_DNS_IP} +short"

### Set up NTP and synchronize time on all hosts
ansible all -m package -a 'name=ntp state=present'
ansible all -o -m shell -a 'timedatectl set-ntp true'
ansible all -o -m shell -a "timedatectl set-timezone ${POC_TZ}"
ansible all -m service -a "name=ntpd state=stopped"
ansible all -o -m shell -a 'ntpd -gq'
ansible all -m service -a "name=ntpd state=started"
sleep 10
ansible all -m shell -a 'ntpstat'
ansible all -m shell -a 'timedatectl status | grep "NTP synchronized:"'
ansible all -m shell -a 'date'

set +x 
