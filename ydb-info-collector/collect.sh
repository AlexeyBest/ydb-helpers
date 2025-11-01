#!/bin/bash

# Variables
ssh_user="yc-user"
# How to create YDB profile: https://ydb.tech/docs/ru/reference/ydb-cli/profile/create
ydb_profile_name="main"
# Path to YDB CLI binary
# How to install: https://ydb.tech/docs/ru/reference/ydb-cli/install
ydb_bin_path="ydb"

# Output directory
dir=output_$(date +'%Y%m%d_%H%M%S')
output_dir="output/$dir"
echo "Start time: $(date +'%Y-%m-%d %H:%M:%S')"
echo -e "Output dir is $output_dir\n"

mkdir -p $output_dir

# Collect info from hosts
echo -e "Collect info from hosts"
hosts=$(cat hosts.txt)
for host in ${hosts[@]}; do
    echo -e "\tCollect info from: $host"

    ssh -o StrictHostKeyChecking=no $ssh_user@$host "sudo sysctl -a" > $output_dir/host_${host}_sysctl.out
    ssh -o StrictHostKeyChecking=no $ssh_user@$host "sudo systemctl status 'ydbd*'" > $output_dir/host_${host}_systemctl.out
    ssh -o StrictHostKeyChecking=no $ssh_user@$host "sudo cat /proc/cpuinfo" > $output_dir/host_${host}_cpuinfo.out
    ssh -o StrictHostKeyChecking=no $ssh_user@$host "free -mh" > $output_dir/host_${host}_memory.out
    ssh -o StrictHostKeyChecking=no $ssh_user@$host "sudo ps -aux | grep ydbd" > $output_dir/host_${host}_processes.out
    ssh -o StrictHostKeyChecking=no $ssh_user@$host "sudo uname -a" > $output_dir/host_${host}_uname.out
done

echo -e "\nCollect info from YDB"

# YDB healthcheck
echo -e "\tHealthcheck"
$ydb_bin_path -p $ydb_profile_name monitoring healthcheck --format json > $output_dir/ydb_healthcheck.json

# YDB configuration
echo -e "\tConfiguration"
$ydb_bin_path -p $ydb_profile_name admin cluster config fetch > $output_dir/ydb_config.yaml

# YDB latency check
echo -e "\tLatency check (long operation)"
$ydb_bin_path -p $ydb_profile_name debug latency > $output_dir/ydb_latency.out

# YDB ping check
echo -e "\tPing check"
$ydb_bin_path -p $ydb_profile_name debug ping > $output_dir/ydb_ping.out

# Pack directory
echo -e "\tPack output"
tar czf $dir.tar.gz $output_dir
rm -r $output_dir

echo -e "\nDone: $(date +'%Y-%m-%d %H:%M:%S')"
echo -e "Output file: $(pwd)/$dir.tar.gz"