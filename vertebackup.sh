#!/bin/bash
#
# rsync-based system backups using hard links
# to reduce disk space requirements.
#
# Author:	Alan Orth
# Version:	0.3

DATE=$(date "+%Y-%m-%dT%H:%M:%S")

# check if the user passed us the UUID of the backup partition
if [ -z $1 ]
then
    echo 'Error: please pass the UUID of the backup partition as an argument to this script, ex:' 1>&2
    echo "	$0 bdd15f9f-ef1a-4643-89fd-c672d1b92c43" 1>&2
    echo 'You can find the UUID of your backup partition using the `blkid` tool.' 1>&2
    exit 256
fi

# try to find the partition's device name from its UUID
DEVICE=$(/sbin/blkid -U $1)
if [ -z $DEVICE ]
then
	echo 'Error: partition with given UUID not found, please check again' 1>&2
	exit 256
fi

# try to find the partition's mountpoint from its device name
MOUNTPOINT=$(mount | grep $DEVICE | awk '{print $3}')
if [ -z $MOUNTPOINT ]
then
	echo 'Error: partition not mounted, please mount it and try again' 1>&2
	exit 256
fi

# set the destination directory on the backup volume
DESTINATION=$MOUNTPOINT/backups

# the number of days of backups to keep
NUMDAYS=14

# a list of files to include/exclude.
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

### END OF USER CONFIGURATION ###

echo "System information"
echo "------------------"
date
uname -a
hostname
echo "------------------"
echo

# set NUMDAYS to NUMDAYS - 1 because we're smarter than the user
let NUMDAYS=NUMDAYS-1

# make sure the backup directories exist
echo "Checking for backup folders..."

# Note: use eval to get proper brace expansion of the 0..$NUMDAYS sequence
for i in $(eval echo {0..$NUMDAYS})
do
	/bin/mkdir -p $DESTINATION/backup.$i
done

# Delete the oldest backup ($NUMDAYS old)
if [ -d $DESTINATION/backup.$NUMDAYS ]
then
	echo "Removing $DESTINATION/backup.$NUMDAYS..."
	/bin/rm -rf $DESTINATION/backup.$NUMDAYS
fi

# Rotate backups starting from the oldest (13 becomes 14, 12 becomes 13, etc)
echo 'Rotating backups...'
for i in $(eval echo {$NUMDAYS..2})
do
	echo "	backup.$[${i}-1] -> backup.$i..."
	/bin/mv $DESTINATION/backup.$[${i}-1] $DESTINATION/backup.$i
done

# Check to make sure backup.0 isn't empty!  If it is, we don't want to
# rotate it, as it will be the "initial" backup.
BACKUP0_CONTENTS=$(ls $DESTINATION/backup.0 | wc -l)
if [ $BACKUP0_CONTENTS -eq 0 ]
then
	# backup.0 is empty, meaning we've never done an "initial" backup!
	# Create backup.1, as it was rotated above.
	echo "Looks like this is going to be the first backup; creating proper directories..."
	echo "	Creating backup.1..."
	/bin/mkdir -p $DESTINATION/backup.1
else
	# looks like backup.0 ain't empty, so rotate it!
	echo "	backup.0 -> backup.1..."
	/bin/mv $DESTINATION/backup.0 $DESTINATION/backup.1
fi

echo "About to backup to $DESTINATION/backup.0..."

# Run the backup, using the last backup as a reference. If a file
# hasn't changed since the reference, hard link it instead of
# copying it again.
#schedtool -B -e nice -n19 ionice -c2 -n7 rsync -az --inplace --numeric-ids --delete-excluded --exclude-from=$BACKUP_LIST_FILE --link-dest=$DESTINATION/backup.1 / $DESTINATION/backup.0/
nice -n19 ionice -c2 -n7 rsync -az --inplace --numeric-ids --delete-excluded --exclude-from=$BACKUP_LIST_FILE --link-dest=$DESTINATION/backup.1 / $DESTINATION/backup.0/

# clean up
echo "Clean up..."
echo "	Deleting $BACKUP_LIST_FILE..."
/bin/rm -f $BACKUP_LIST_FILE

exit 0
