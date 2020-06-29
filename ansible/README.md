# Ansible Playbooks for Vertica Eon PoC

## Command Host Setup

Run scripts to configure the command host/vm for the PoC:

1. Customize environment variables
2. Install basic packages
3. Generate SSH setup for the PoC
4. Switch networking to use files
5. Set up local DNS server with /etc/hosts and dnsmasq
6. Install and configure Ansible
7. Set up NTP and synchronize time

## Playbook Run Order
1. hosts-packages.yml
2. hosts-docker.yml
3. fb-prep-poc.yml
4. user-root.yml
5. user-dbadmin.yml
6. hosts-go.yml
7. hosts-s5cmd.yml
8. hosts-mount.yml
9. vertica-prep.yml
10. vertica-check.yml
11. vertica-package.yml
12. vertica-console.yml
 - Install locally on command VM
13. vertica-vcpuperf.yml
14. vertica-vioperf.yml
15. vertica-vnetperf-metal.yml
16. vertica-vnetperf-vm.yml
17. vertica-seed-cluster.yml
18. vertica-new-db.yml
19. vertica-vmart.yml

### Optional Playbooks
- vertica-tuned.yml



