#!/usr/bin/env bash

#######################################################
### Source this file to set all the needed environment
### variables from one replace prior to running the
### cloning and DR test playbooks
#######################################################

if [[ "$(basename -- "$0")" == "source_me.sh" ]]; then
    echo "Don't run $0, source it in a terminal window prior to running the playbook" >&2
    exit 1
fi

# set -x

### Common info #######################################################
# Vertica database admin user
export RUN_AS="dbadmin"
# Maximum replication lag between FlashBlades to wait before trying revive
export LAG_MAX_WAIT="900"
# Whether to flush internal stats and delete old data prior to replication (rarely useful)
export FLUSH_SOURCE="no"
# Table in default schema to use for simple count(*) test
export CANARY_TABLE="WebPages"

### Source-side info for the DR demo
# Source (and cloning) FlashBlade Management IP address
export SRC_FB_MGMT="10.99.100.100"
# Source (and cloning) FlashBlade Data IP address
export SRC_FB_DATA="10.99.100.101"
# Source (and cloning) FlashBlade API Token
# See https://github.com/microslav/vertica-poc#set-the-flashblade-api-token for more info
export SRC_FB_API="T-deadbeef-f00d-cafe-feed-1337c0ffee"
# Bucket on the Source (and clone) side used for communal storage
export SRC_BUCKET="bos"
# Object key prefix within the bucket where the source database lives
export SRC_PREFIX="/prod/"
# AWS config and credentials profile to use on the source side
export SRC_AWS_PROFILE="default"
# Alias for s5cmd used on the source side (shouldn't need to be changed)
export SRC_S5="AWS_PROFILE=${SRC_AWS_PROFILE} s5cmd --endpoint-url=http://${SRC_FB_DATA}:80"

### Destination/Target-side info for the DR demo
# Destination FlashBlade Management IP address
export DST_FB_MGMT="10.99.101.100"
# Destination FlashBlade Data IP address
export DST_FB_DATA="10.99.101.101"
# Destination FlashBlade API Token
# See https://github.com/microslav/vertica-poc#set-the-flashblade-api-token for more info
export DST_FB_API="T-deadbeef-f00d-cafe-feed-1337c0ffee"
# Bucket on the destination side used as the replication target
export DST_BUCKET="bos-dr"
# Object key prefix to substitute for the source prefix in the cloned path
export DST_PREFIX="/test/"
# AWS config and credentials profile to use on the destination side
export DST_AWS_PROFILE="default"
# Alias for s5cmd used on the destination side (shouldn't need to be changed)
export DST_S5="AWS_PROFILE=${DST_AWS_PROFILE} s5cmd --endpoint-url=http://${DST_FB_DATA}:80"
# Path to auth_params.conf file used on the destination cluster for DR testing (DR target FlashBlade endpoint)
export DST_DR_AUTH="/home/${RUN_AS}/dr_auth_params.conf"
# Path to auth_params.conf file used on the destination cluster for Cloning testing (source FlashBlade endpoint)
export DST_CLONE_AUTH="/home/${RUN_AS}/clone_auth_params.conf"

# set +x
