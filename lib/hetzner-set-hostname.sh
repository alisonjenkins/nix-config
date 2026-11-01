#!/usr/bin/env bash
# Put the Hetzner server name back as the kernel hostname on every boot.
# cloud-init's update_hostname applies it once per instance and then sees the
# image's static hostName as user-maintained, so after the first reboot k3s and
# tailscale would register the node under the wrong name.
# Never fails the boot: with no usable name the static hostName stays.
set -euo pipefail

instance_data=${INSTANCE_DATA:-/run/cloud-init/instance-data.json}
hostname_file=${HOSTNAME_FILE:-/proc/sys/kernel/hostname}

if [ ! -r "$instance_data" ]; then
  printf 'event=hetzner-hostname status=skip reason=no-instance-data path=%q\n' "$instance_data" >&2
  exit 0
fi

name=$(jq -r '.v1.local_hostname // empty' "$instance_data")
if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
  printf 'event=hetzner-hostname status=skip reason=no-valid-name name=%q\n' "$name" >&2
  exit 0
fi

printf '%s\n' "$name" > "$hostname_file"
printf 'event=hetzner-hostname status=set name=%q\n' "$name" >&2
