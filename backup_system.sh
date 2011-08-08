#!/bin/bash
#
# rsync-based system backups using hard links
# to reduce disk space requirements.
#
# Author:	Alan Orth
# Version:	0.2

DATE=$(date "+%Y-%m-%dT%H:%M:%S")

# 1. set up the backup directory
# find the partition's device by its UUID (to find a partition's UUID, use 'blkid')
UUID=edit_me
if [ "$UUID" = "edit_me" ]
then
    echo "Error: please edit this script and change the UUID variable" 1>&2
    exit 256
fi

DEVICE=$(/sbin/blkid -U $UUID)

# 2. find out if and where the partition is mounted
MOUNTPOINT=$(mount | grep $DEVICE | awk '{print $3}')

# 3. set the destination directory
DESTINATION=$MOUNTPOINT/backups

# 4. set the number of days of backups to keep
NUMDAYS=14

# 5. a list of files to include/exclude.
BACKUP_LIST_FILE=/tmp/system_backup_$DATE.lst
# customize this to exclude network mounts, the backup dir itself,
# or anything else you're backing up manually etc
#
# a "+" means include
# a "-" means exclude
cat > $BACKUP_LIST_FILE <<LIST
# Include these specifically (acts as a filter against the excludes below)
+ /dev/console
+ /dev/initctl
+ /dev/null
+ /dev/zero

# Exclude certain system folders, but make sure to create the folders themselves
- /dev/*
- /proc/*
- /sys/*
- /tmp/*

# don't backup file system lost+found directories
- *lost+found

# don't backup mounted drives
- /media/*
- /mnt/*

# don't back up package manager cached files (for Debian-based Linuxes)
- /var/cache/apt/archives/*.deb

# don't backup gnome virtual file system (rsync can't read it)
- *.gvfs

# don't backup movies
- *.avi
- *.mp4
- *.mkv
- *.m4v
- *.flv

# don't backup large software installers
- *.iso
- *.img

# backup single homes separately
- /home/*
LIST

# make sure the backup directories exist
# Note: use eval to get proper brace expansion of the 0..$NUMDAYS sequence
for i in $(eval echo {0..$NUMDAYS})
do
	/bin/mkdir -pv ${DESTINATION}/backup.${i}
done

# delete the oldest backup ($NUMDAYS old)
echo "Removing $DESTINATION/backup.${NUMDAYS}..."
/bin/rm -rf $DESTINATION/backup.${NUMDAYS}

# shift backups starting from the oldest (13 becomes 14, 12 becomes 13, etc)
for i in $(eval echo {$NUMDAYS..1})
do
  /bin/mv $DESTINATION/backup.$[${i}-1] $DESTINATION/backup.${i}
done

echo "System information"
echo "------------------"
date
uname -a
hostname
echo "------------------"
echo "About to backup to ${DESTINATION}/backup.0"

# run the backup, using "backup.1" as the reference.
# if a file hasn't changed from the reference,
# hard link it instead of copying it again
nice -n19 ionice -c2 -n7 rsync -az --inplace --numeric-ids --delete-excluded --exclude-from=$BACKUP_LIST_FILE --link-dest=$DESTINATION/backup.1 / $DESTINATION/backup.0/

# clean up
echo "	Clean up (deleting $BACKUP_LIST_FILE)..."
rm $BACKUP_LIST_FILE

exit 0
