# Vertica Ansible roles/primary-node/files/
Put files needed for the Vertica primary node setup and testing tasks. These are:

1. license.key -- Vertica license key for the cluster being set up. Currently contains the Community Edition key (3 nodes, 1TB max). Replace with own key if testing larger clusters.
2. vmart_parallel_load.sql -- SQL for parallelizing data loads across all nodes during VMart test/demo


