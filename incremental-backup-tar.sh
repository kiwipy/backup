#!/bin/bash
#
# This script requires the bc package
#
VERSION=5.5
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

NAME=${0##*/}
TARGET="/path/to/directory" #<----- change
DEST="/location/for/backup" #<----- change
INDEX="$DEST/index"
LOG="$DEST/backup.log"
TIMESTAMP=$(date +%d-%m-%Y)
DATE=$(date +%d-%m-%Y)
MONTH_YEAR=$(date +%b-%Y)
LAST_MONTH_YEAR=$(date --date='-1 month' +%b-%Y)
FREE_SPACE_MARGIN="1.1" #Set a 10% margin for free space

function view_help(){
	echo "$0 Version $VERSION"
	echo "Syntax: $0 --option"
	echo -e "\nOptions:"
	echo -e "--list\t\tList available backups."
	echo -e "--restore\tRestore from backup."
	echo -e "--version\tSame as --help."
	echo -e "--log\t\tShow log messages."
	echo -e "--help\t\tDisplay this text."
}

function msg(){
	# function to echo message with delay
	echo $1
	sleep 1
}

function calc_free_space(){
	msg "Calculating space ..."
	TOTAL_SIZE=$(du -sm $TARGET/ | awk '{print $1}')
	REQUIRED_SPACE=$(echo "$TOTAL_SIZE*$FREE_SPACE_MARGIN" | bc | sed 's/..$//')
	msg "$(echo "$REQUIRED_SPACE/1024" | bc) GB required"
	while true; do	
		AVAILABLE_SPACE=$(df -m | awk -v pat="$DEST" '$0~pat{print $4}')
		msg "$(echo "$AVAILABLE_SPACE/1024" | bc) GB available"
		if [ $AVAILABLE_SPACE -le $REQUIRED_SPACE ]; then
			OLD=$(awk 'NR==1{print}' $INDEX)
			if [ -d "$DEST/$OLD" ]; then
				msg "Removing old backup [$OLD] ..."
				rm -r $DEST/$OLD
				logger -t $NAME "Removed old backup [$OLD]"
			fi
			msg "Updating index file ..."
			sed -i '1d' $INDEX
		else
			msg "Sufficient free space."
			break
		fi
	done
}

function create_backup(){
	if [ ! -d "$DEST/$MONTH_YEAR" ]; then
		msg "Creating directory [$DEST/$MONTH_YEAR]"
		mkdir $DEST/$MONTH_YEAR
		msg "Creating new full backup ..."
		cd $TARGET
		tar --exclude={'lost+found','.Trash-1000'} -cpf $DEST/$MONTH_YEAR/$DATE.tar -g $DEST/$MONTH_YEAR/snar *
		echo "$DATE.tar" > $DEST/$MONTH_YEAR/index
		logger -t $NAME "Created new full backup [$MONTH_YEAR/$DATE.tar]"
		msg "Updating index file ..."
		echo $MONTH_YEAR >> $INDEX
		#archive_previous_month
	else
		msg "Creating incremental backup ..."
		cd $TARGET
		tar --exclude={'lost+found','.Trash-1000'} -cpf $DEST/$MONTH_YEAR/$DATE.tar -g $DEST/$MONTH_YEAR/snar *
		echo "$DATE.tar" >> $DEST/$MONTH_YEAR/index
		logger -t $NAME "Created incremental backup [$MONTH_YEAR/$DATE.tar]"
	fi
}

function restore_from_backup(){
	list_backups
	echo -e "\n## Select backup to restore ##"
	read -p "Select [MONTH-YEAR]: " SELECT_MY
	if [ -f "$DEST/$SELECT_MY.tar.gz" ]; then
		ARCHIVE=1
		tar -tf $DEST/$SELECT_MY.tar.gz
	else
		ARCHIVE=0
		for dir in $(ls $DEST/$SELECT_MY); do
			echo "./$dir"
		done
	fi
	read -p "Select [DAY]: " SELECT_D
	read -p "Select absolute path: " SELECT_PATH
	SELECT_DMY="$SELECT_D.tar"
	echo "Restore from backup [$SELECT_DMY] to path $SELECT_PATH"
	read -p "Continue? [y/n]: " q
	if [ "$q" == "y" ]; then
		if [ "$ARCHIVE" == "1" ]; then
			msg "Unpacking archive $DEST/$SELECT_MY.tar.gz ..."
			tar -xf $DEST/$SELECT_MY.tar.gz $DEST/
		fi
		msg "Start restoring from backup ..."
		for arch in $(cat "$DEST/$SELECT_MY/index"); do
			if [ "$arch" == "$SELECT_DMY" ]; then
				msg "Restoring $arch to $SELECT_PATH ..."
				tar -xf $DEST/$SELECT_MY/$arch -g /dev/null -C $SELECT_PATH
				msg "Backup has been restored!"
				exit 0
			else
				msg "Restoring $arch to $SELECT_PATH ..."
				tar -xf $DEST/$SELECT_MY/$arch -g /dev/null -C $SELECT_PATH
			fi
		done
	else
		exit 0
	fi
}

function list_backups(){
	msg "## Available backups ##"
	for bak in $(cat $INDEX); do
		echo "* $bak - $(du -sh $DEST/$bak | awk '{print $1}')"
	done
}


### Script starts here! ###
if [ "$1" == "--version" ] || [ "$1" == "--help" ]; then
	view_help
	exit 0
elif [ "$1" == "--restore" ]; then
	restore_from_backup
	exit 0
elif [ "$1" == "--list" ]; then
	list_backups
	exit 0
elif [ "$1" == "--log" ]; then
	journalctl -t $NAME
	exit 0
else
	if [ ! -d "$TARGET" ]; then
		echo "No target directory!"
		logger -t $NAME "No target directory found!"
		exit 1
	elif [ ! -d "$DEST" ]; then
		echo "No destination directory!"
		logger -t $NAME "No destination directory found!"
		exit 1
	fi
	msg "Starting backup process!"
	sleep 1
	calc_free_space
	create_backup
	echo "Done."
	exit 0
fi
