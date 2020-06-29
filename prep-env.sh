#!/usr/bin/bash 

######################################################################
### prep-env.sh -- Script to configure a command host/vm to act as
###                the central point of control for the PoC. Run it
###                on the host you want to use for command of the PoC
######################################################################

######################################################################
### Set up environment details -- REQUIRED REQUIRED REQUIRED 
###
### Edit the values for the environment variables below to fit with 
### the PoC host and network environment you have available.
######################################################################

### Unique prefix to use for this PoC (e.g., customer name)
export POC_PREFIX="choam"

### Initial packages to install before Ansible configured
export INITPKG="mosh tmux emacs-nox emacs-yaml-mode"
export DNSPKG="dnsmasq bind-utils"

### SSH Keys to create or use
export KEYNAME="${POC_PREFIX}-poc"
export KEYPATH="${HOME}/.ssh/${KEYNAME}"

### For dnsmasq setup
export HOSTNAME_ORIG=$(hostname)             # Remember the original hostname
export HOSTNAME_C3="${POC_PREFIX}-command"   # Add alias based on PoC name
export LAB_DOM="vertica.lab"                 # The domain created for the PoC
export LAB_GW="10.23.26.1"                   # Gateway for the management network
export LAB_IP_SUFFIX="100"                   # IP address suffix for the command host (all networks)
export LAB_MGMT_NET="10.23.26"               # Prefix for the Management network (expecting /24)
export LAB_PRIV_NET="10.4.26"                # Prefix for Private node network (expecting /24)
export LAB_STOR_NET="10.7.26"                # Prefix for S3 Storage network (expecting /24) 
export LAB_RDNS_MGMT="$(echo $LAB_MGMT_NET | awk -F. '{print $3 "." $2 "." $1}').in-addr.arpa"
export LAB_RDNS_VERT="$(echo $LAB_PRIV_NET | awk -F. '{print $3 "." $2 "." $1}').in-addr.arpa"
export LAB_RDNS_STOR="$(echo $LAB_STOR_NET | awk -F. '{print $3 "." $2 "." $1}').in-addr.arpa"
export LAB_DNS_IP="${LAB_MGMT_NET}.${LAB_IP_SUFFIX}"
export POC_DOM="csc.purestorage.com"         # External domain hosting the PoC
export POC_DNS="10.21.93.16"                 # External DNS server to use

######################################################################
### Basics -- Assuming a Centos 7.7+ environment
######################################################################

# Install basic packages
yum install -y epel-release
yum install -y deltarpm
yum install -y $INITPKG

# Set up SSH keys for key-based remote access
[[ -d ${HOME}/.ssh ]] || mkdir -m 700 ${HOME}/.ssh
[[ -f $KEYPATH ]] || ssh-keygen -f $KEYPATH -q -N ""
[[ -L ${HOME}/.ssh/vertica-poc ]] || ln -s $KEYPATH ${HOME}/.ssh/vertica-poc
[[ -L ${HOME}/.ssh/vertica-poc.pub ]] || ln -s ${KEYPATH}.pub ${HOME}/.ssh/vertica-poc.pub
cat <<_EOF_ >> ${HOME}/.ssh/config
Host *
   IdentityFile ${KEYPATH}
   StrictHostKeyChecking no
   UserKnownHostsFile=/dev/null
_EOF_

# Disable NetworkManager and use files instead
systemctl stop NetworkManager
systemctl disable NetworkManager
systemctl enable network.service
systemctl start network.service

######################################################################
### DNS -- Set up command host as DNS server for PoC
######################################################################

# Install and configure dnsmasq (https://www.tecmint.com/setup-a-dns-dhcp-server-using-dnsmasq-on-centos-rhel/)
yum install -y $DNSPKG
cp /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
cat <<_EOF_  > /etc/dnsmasq.conf
domain-needed
bogus-priv
no-resolv
no-poll
server=/${LAB_DOM}/127.0.0.1
server=/${POC_DOM}/${POC_DNS}
server=8.8.8.8
server=8.8.4.4
server=/${LAB_RDNS_MGMT}/127.0.0.1
server=/${LAB_RDNS_VERT}/127.0.0.1
server=/${LAB_RDNS_STOR}/127.0.0.1
local=/${LAB_DOM}/
expand-hosts
domain=${LAB_DOM}
_EOF_

# Configure details of the PoC environment in /etc/hosts
# REQUIRED -- Edit the entries below to match the PoC hosts and networks
# that you have available for this PoC 
mv /etc/hosts /etc/hosts.orig
cat <<_EOF_ > /etc/hosts
${LAB_MGMT_NET}.${LAB_IP_SUFFIX} ${HOSTNAME_C3} ${HOSTNAME_ORIG} command ns1 www
${LAB_PRIV_NET}.${LAB_IP_SUFFIX}  ${HOSTNAME_C3}-priv command-priv
${LAB_STOR_NET}.${LAB_IP_SUFFIX}  ${HOSTNAME_C3}-data command-data

10.23.26.13 ${POC_PREFIX}-01 vertica-01 vertica-mgmt-01
10.23.26.15 ${POC_PREFIX}-02 vertica-02 vertica-mgmt-02
10.23.26.17 ${POC_PREFIX}-03 vertica-03 vertica-mgmt-03
10.23.26.19 ${POC_PREFIX}-04 vertica-04 vertica-mgmt-04
10.23.26.21 ${POC_PREFIX}-05 vertica-05 vertica-mgmt-05
10.23.26.23 ${POC_PREFIX}-06 vertica-06 vertica-mgmt-06

10.4.26.13 vertica-priv-01
10.4.26.15 vertica-priv-02
10.4.26.17 vertica-priv-03
10.4.26.19 vertica-priv-04
10.4.26.21 vertica-priv-05
10.4.26.23 vertica-priv-06

# FlashBlade details
10.23.26.30  ${POC_PREFIX}-fb-mgmt poc-fb-mgmt
${LAB_STOR_NET}.201 ${POC_PREFIX}-fb-data-01 poc-fb-data-01
${LAB_STOR_NET}.202 ${POC_PREFIX}-fb-data-02 poc-fb-data-02

127.0.0.1    localhost localhost4 
::1          localhost localhost6 
_EOF_

# Test and set up the dnsmasq service to automatically restart
dnsmasq --test
firewall-cmd --permanent --zone=public --add-service=dns
systemctl start dnsmasq
systemctl enable dnsmasq
systemctl status dnsmasq

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

systemctl daemon-reload
systemctl restart dnsmasq
systemctl status dnsmasq

mv /etc/resolv.conf /etc/resolv.orig
cat <<_EOF_ > /etc/resolv.conf
search ${LAB_DOM}
nameserver ${LAB_DNS_IP}
_EOF_

cat <<_EOF_ > /etc/sysconfig/network
GATEWAY=${LAB_GW}
_EOF_

# Set the hostname if it doesn't already match the expected name
[[ "$(hostname)" == "${HOSTNAME_C3}" ]] || hostnamectl set-hostname ${HOSTNAME_C3}


######################################################################
### Install and configure Ansible
######################################################################
yum install -y ansible

### Set the global Ansible hosts file
### REQUIRED -- Edit to match your PoC environment
mv /etc/ansible/hosts /etc/ansible/hosts_orig
cat <<_EOF_ > /etc/ansible/hosts
[local]
localhost
[local:vars]
ansible_ssh_private_key_file=${KEYPATH}

[vertica]
vertica-0[1:6]
[vertica:vars]
ansible_ssh_private_key_file=${KEYPATH}
_EOF_

# Configure Ansible to use bash shell and more parallelism
cp /etc/ansible/ansible.cfg /etc/ansible/ansible.cfg_orig
sed -i 's/^#forks\s*=\s*5/forks = 20/g' /etc/ansible/ansible.cfg
sed -i 's|^#executable\s*=\s*/bin/sh|executable = /bin/bash|g' /etc/ansible/ansible.cfg

# Set up SSH authentication for Vertica hosts (say 'yes' and enter password repeatedly)
for n in $(seq -f%02g 1 6); do ssh-copy-id -i $KEYPATH vertica-${n} ; done

# Test that Ansible is working 
ansible all -o -m ping

# Configure PoC hosts to use Command host for DNS
ansible all -o -m package -a 'name=bind-utils state=latest'
ansible vertica -o -m shell -a 'systemctl stop NetworkManager'
ansible vertica -o -m shell -a 'systemctl disable NetworkManager'
ansible vertica -o -m shell -a 'systemctl enable network.service'
ansible vertica -o -m shell -a 'systemctl start network.service'
ansible vertica -o -m copy -a 'src=/etc/resolv.conf dest=/etc/resolv.conf'
ansible vertica -o -m copy -a 'src=/etc/sysconfig/network dest=/etc/sysconfig/network'
ansible vertica -o -m shell -a 'dig command google.com +short'
ansible vertica -o -m shell -a "dig -x ${LAB_DNS_IP} +short"

# Set up all hosts to use NTP and synchronize
ansible all -o -m package -a 'name=ntp state=latest'
ansible all -o -m shell -a 'timedatectl set-ntp true'
ansible all -o -m shell -a 'timedatectl set-timezone America/Los_Angeles'
ansible all -o -m shell -a 'timedatectl status'
ansible all -o -m shell -a 'date'
