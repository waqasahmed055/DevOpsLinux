#!/bin/bash

# Change this if your disk is different
DISK="/dev/sdb"
PARTITION="${DISK}1"
MOUNT_POINT="/data"

set -e

echo "==== Checking disk ===="
lsblk "$DISK"

echo "==== Creating GPT partition table ===="
sudo parted -s "$DISK" mklabel gpt

echo "==== Creating partition ===="
sudo parted -s "$DISK" mkpart primary ext4 0% 100%

echo "==== Informing kernel about partition changes ===="
sudo partprobe "$DISK"

sleep 2

echo "==== Creating ext4 filesystem ===="
sudo mkfs.ext4 -F "$PARTITION"

echo "==== Creating mount point ===="
sudo mkdir -p "$MOUNT_POINT"

echo "==== Getting UUID ===="
UUID=$(sudo blkid -s UUID -o value "$PARTITION")

echo "==== Updating /etc/fstab ===="
if ! grep -q "$UUID" /etc/fstab; then
    echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 0" | sudo tee -a /etc/fstab
fi

echo "==== Mounting filesystem ===="
sudo mount -a

echo "==== Final disk status ===="
lsblk
df -h | grep "$MOUNT_POINT"

echo "==== Completed successfully ===="
