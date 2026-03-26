#!/bin/bash

# Initial variables:
FSTAB=/etc/fstab
MOUNTPOINT=/var/log
TEMPFOLDER=/var/log_old
TARGET_GiB=$1

########

if [ -z $1 ]; then
	echo "Disk size in GiB is not specified - aborting."
	exit 1
fi

if grep -q $MOUNTPOINT $FSTAB; then
	echo "$MOUNTPOINT filesystem already appears in $FSTAB - aborting."
	exit 1
fi

# Check that a temporal folder for logs does not already exist
if [ -e $TEMPFOLDER ]; then
  echo "Temporary directory $TEMPFOLDER already exists - aborting."
  exit 1
fi

# Identify the disk
TARGET_BYTES=$((TARGET_GiB * 1024 * 1024 * 1024))
TARGET_DISK=$(lsblk -b -o NAME,SIZE,TYPE -n | awk -v size="$TARGET_BYTES" '$2 == size && $3 == "disk" {print "/dev/"$1; exit}')

if [ -z "$TARGET_DISK" ]; then
	echo "No disk with size ${TARGET_GiB} GiB found."
	exit 1
fi

# Check whether the disk is already formatted
FS_TYPE=$(lsblk -dn -o FSTYPE $TARGET_DISK)
if [ -n "$FS_TYPE" ]; then
    echo "Disk $TARGET_DISK is already formatted as $FS_TYPE - aborting."
    exit 1
fi

echo "Disk $TARGET_DISK appears to be empty/unformatted. Proceeding to format..."
wipefs -a "$TARGET_DISK"
mkfs.ext4 "$TARGET_DISK"

# Get UUID of the created filesystem
UUID=$(blkid -s UUID -o value "$TARGET_DISK")
if [ -z "$UUID" ]; then
	echo "Error: Could not retrieve UUID for $PARTITION"
	exit 1
fi
echo "Success: $TARGET_DISK formatted as ext4, with UUID $UUID"

# Add the new entry to /etc/fstab:
echo "Adding entry to $FSTAB"
echo "UUID=$UUID  $MOUNTPOINT  ext4  defaults  0  2" >> $FSTAB

# Move existing /var/log contents temporarily to /var/log_old:
mv $MOUNTPOINT $TEMPFOLDER
mkdir $MOUNTPOINT
chmod 755 $MOUNTPOINT

# Mount /var/log to the dedicated disk:
systemctl daemon-reload
mount -a

# move existing logs back and clean up
cp -a "$TEMPFOLDER"/. "$MOUNTPOINT"/
rm -fr $TEMPFOLDER
