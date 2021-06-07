# FlashBlade Object Cloning for Vertica Eon mode

This repository contains example Ansible playbooks with code related to cloning Vertica databases on Pure Storage FlashBlades. There are two main examples, aligned with the two most common use cases:

1. **Test/Dev for production databases** — Cloning a database on the same FlashBlade where the production database operates. This example is in the [vertica-clone-db.yml](https://github.com/microslav/vertica-cloning/blob/main/vertica-clone-db.yml) playbook.
2. **Validation testing for DR database copies** — Cloning from a DR copy of a production database being continuously replicated via FlashBlade Object Replication. This example is in the [vertica-test-dr.yml](https://github.com/microslav/vertica-cloning/blob/main/vertica-test-dr.yml) playbook.

While these examples will likely work with minor modification for many environments, they're meant to be adapted for before being used in production. The rest of this README file explains the structure of the playbooks and how to customize them for experiments.

## Setting Up

### Assumptions
- The base assumption is that you already have a Vertica PoC environment where you can experiment with this functionality.
- That environment is already configured with Ansible, the right versions of Python, and the [Pure Storage FlashBlade collection from Ansible Galaxy](https://galaxy.ansible.com/purestorage/flashblade).
- The code is being run from the Management Console node (`mc`), and that node has the FlashBlade collection from Ansible Galaxy. It doesn't have to be the MC host if there isn't one; a regular test host with the right setup and keys will work too. Use `git clone` to get a copy of this repository onto that node.
- The playbooks use the `root` user to connect to the Ansible hosts. When they need to execute commands as the Vertica DB user, they use `run_as`.

The code in this repo was developed and tested using the Vertica PoC environment set up using the [playbooks in the Vertica PoC repository](https://github.com/microslav/vertica-poc). It might be useful option if you're starting from scratch or evaluating Vertica Eon mode.

### Customizations

1. Modify the [hosts.ini file](https://github.com/microslav/vertica-cloning/blob/main/hosts.ini) to match your testing environment. There are four main host groups:
   1. `mc` — the Management Console host where the playbooks are going to run
   2. `src_cluster` — the group of hosts that constitute a (sub)cluster providing the source database that will be cloned.
   3. `dr_cluster` — the group of hosts that will be used to revive the clone of the DR database copy at the DR destination site.
   4. `test_cluster` – the group of hosts that will be used for test/dev work at the primary site where the production database lives.
2. Modify the `ansible_user` and `ansible_ssh_private_key_file` variables in the hosts.in file to point to the appropriate user and files. The playbooks use `su` as the `become_method` to become the Vertica DB user, so the ansible_user needs to be able to do that. Otherwise, you may need to modify the method to something that works for you.
3. Set the appropriate values in the [source_me.sh file](https://github.com/microslav/vertica-cloning/blob/main/source_me.sh). These are used to set the environment variables picked up by the playbooks and configure the infrastructure details during the run. Each variable includes a comment explaining that it does and how it should be set. If you're testing with a single site and FlashBlade (e.g., Test/Dev cloning), there's no need to set the Destination variables.

## Running the Playbooks

Once you've made the customizations, running the playbooks is simple:

1. Go into the directory where this code got installed. If you need to activate a Python virtual environment to get access to the right versions and paths, do so.
2. Source (don't execute) the `source_me.sh` file in that terminal session. This will make the configuration variables available in the environment for the playbooks to pick up during the run. If you need to change a particular variable afterwards during testing, you can either edit and source the file again, or just export a new value from the command line.
3. Run the playbook for the scenario you want to test, specifying the local `hosts.ini` file as the source of the host definitions:
   1. Test/Dev Cloning — `ansible-playbook -i hosts.ini vertica-clone-db.yml`
   2. DR Validation — `ansible-playbook -i hosts.ini vertica-test-dr.yml`

There might be certain assumptions of configurations in the playbook code that don't match your environment. If that's the case, either change them in the playbook, or parameterize them and add the new parameters to the `source_me.sh` file.
