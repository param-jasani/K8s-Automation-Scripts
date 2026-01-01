#!/bin/bash
# This script unmounts /data, wipes any existing filesystem signatures,
# and clears the first 1 MB of /dev/sda6. This prepares the device as a raw block
# for use with cpeh fs.
#
# WARNING: Running this script will destroy any data on /dev/sda6.
# Make sure you have the correct device and that the partition is not in use.

set -euo pipefail

DEVICE="/dev/sda6"
sudo mkfs.ext4 $DEVICE
MOUNTPOINT="/data"

# Ensure the script is run as root.
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Exiting."
    exit 1
fi

echo "---- Unmounting $MOUNTPOINT if it is mounted ----"
if mountpoint -q "$MOUNTPOINT"; then
    echo "$MOUNTPOINT is currently mounted. Unmounting..."
    umount "$MOUNTPOINT"
    echo "Successfully unmounted $MOUNTPOINT."
else
    echo "$MOUNTPOINT is not mounted."
fi

echo "---- Displaying current filesystem signatures on $DEVICE ----"
wipefs "$DEVICE" || echo "No signatures found."

echo "---- Removing all filesystem signatures from $DEVICE ----"
wipefs -a "$DEVICE"

echo "---- Overwriting the first 1 MB of $DEVICE with zeros ----"
dd if=/dev/zero of="$DEVICE" bs=1M count=1 status=progress

echo "---- Verifying that $DEVICE is clean ----"
wipefs "$DEVICE"
echo "Device $DEVICE is now clean and ready for use as a raw block device for cpeh fs."

echo "Preparation complete!"
