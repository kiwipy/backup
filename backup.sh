#!/bin/bash
#
# Copyright William Andersson 2024
# https://github.com/william-andersson
#
VERSION=6.0
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

NAME=${0##*/}
source /etc/toolbox-backup.cfg
INDEX="$DEST/index"
TIMESTAMP=$(date +%d-%m-%Y)
DATE=$(date +%d-%m-%Y)
MONTH_YEAR=$(date +%b-%Y)
LAST_MONTH_YEAR=$(date --date='-1 month' +%b-%Y)
FREE_SPACE_MARGIN="1.1" #10%

function view_help(){
	echo -e "$NAME Version $VERSION"
	echo -e "\nIMPORTANT: This script can only cope with one option at a time"
	echo -e "\t\tand in exact order described under usage.\n"
	echo -e "\t\tCurrent source path: $SRC"
	echo -e "\t\tCurrent dest path: $DEST"
	echo -e "\nUsage:"
	echo -e " --source <PATH>\t\tSet SOURCE directory."
	echo -e " --dest <PATH>\t\t\tSet DESTINATION directory."
	echo -e " --migrate <PATH>\t\tMove entire backup directory."
	echo ""
	echo -e " --restore [DATE] <PATH>\tRestore from backup,"
	echo -e " \t\t\t\t  DATE format should be: yyyy-mm-dd"
	echo -e " \t\t\t\t  or leave blank for most recent."
	echo -e " --list [DATE]\t\t\tList available backups,"
	echo -e " \t\t\t\t  DATE format should be: Jan-yyyy"
	echo -e " \t\t\t\t  or leave blank for whole month and size."
	echo ""
	echo -e " --remove\t\t\tManually remove the oldest backup."
	echo -e " --log\t\t\t\tShow log messages."
	echo -e " --version\t\t\tSame as --help."
	echo -e " --help\t\t\t\tDisplay this text."
}

function msg(){
	echo $1
	sleep .2
}

function list_backups(){
	if [ ! $1 ];then
		msg "## Available backups ##"
		for bak in $(cat $INDEX); do
			echo "* $bak - $(du -sh $DEST/$bak | awk '{print $1}')"
		done
	else
		msg "## $1 ##"
		cat $DEST/$1/index
	fi
}

function set_source(){
	TRIM_PATH=${1%/}
	if [ ! $1 ];then
		echo "No selected path!"
		exit 1
	else
		sed -i 's:'$SRC':'$TRIM_PATH':' /etc/toolbox-backup.cfg
		msg "Changed source $SRC -> $TRIM_PATH"
		logger -t $NAME "Source directory changed [$TRIM_PATH]"
	fi
}

function set_dest(){
	TRIM_PATH=${1%/}
	if [ ! $1 ];then
		echo "No selected path!"
		exit 1
	else
		sed -i 's:'$DEST':'$TRIM_PATH':' /etc/toolbox-backup.cfg
		msg "Changed destination $DEST -> $TRIM_PATH"
		logger -t $NAME "Destination directory changed [$TRIM_PATH]"
		if [ ! -d "$TRIM_PATH" ];then
			mkdir -v $TRIM_PATH
		fi
	fi
}

function migrate(){
	TRIM_PATH=${1%/}
	if [ ! $1 ];then
		echo "No selected path!"
		exit 1
	else
		rsync --remove-source-files -ah $DEST/ $TRIM_PATH --info=progress2
		logger -t $NAME "Backup directory migrated to [$TRIM_PATH]"
		msg "Backup directory migrated to [$TRIM_PATH]"
		rm -rv $DEST
		set_dest $1
	fi
}

function remove_old_backup(){
	OLD=$(awk 'NR==1{print}' $INDEX)
		if [ -d "$DEST/$OLD" ]; then
			msg "Removing old backup [$OLD] ..."
			rm -r $DEST/$OLD
			logger -t $NAME "Removed old backup [$OLD]"
		fi
		msg "Updating index file ..."
		sed -i '1d' $INDEX
}

function calc_free_space(){
	msg "Calculating space ..."
	TOTAL_SIZE=$(du -sm $SRC/ | awk '{print $1}')
	REQUIRED_SPACE=$(echo "$TOTAL_SIZE*$FREE_SPACE_MARGIN" | bc | sed 's/..$//')
	msg "$(echo "$REQUIRED_SPACE/1024" | bc)GB required"
	while true; do	
		AVAILABLE_SPACE=$(df -m $DEST | tail -1 | awk '{print $4}')
		msg "$(echo "$AVAILABLE_SPACE/1024" | bc)GB available"
		if [ $AVAILABLE_SPACE -le $REQUIRED_SPACE ]; then
			remove_old_backup
		else
			msg "Sufficient free space."
			break
		fi
	done
}

function create_backup(){
	if [ ! -d "$SRC" ]; then
		echo "No source directory!"
		logger -t $NAME "No source directory found!"
		exit 1
	elif [ ! -d "$DEST" ]; then
		echo "No destination directory!"
		logger -t $NAME "No destination directory found!"
		exit 1
	fi
	calc_free_space
	msg "Starting backup process!"
	if [ ! -d "$DEST/$MONTH_YEAR" ]; then
		msg "Creating directory [$DEST/$MONTH_YEAR]"
		mkdir $DEST/$MONTH_YEAR
		msg "Creating new full backup ..."
		cd $SRC
		tar --exclude={'lost+found','.Trash-1000'} -cpf $DEST/$MONTH_YEAR/$DATE.tar -g $DEST/$MONTH_YEAR/snar *
		echo "$DATE.tar" > $DEST/$MONTH_YEAR/index
		logger -t $NAME "Created new full backup [$MONTH_YEAR/$DATE.tar]"
		msg "Updating index file ..."
		echo $MONTH_YEAR >> $INDEX
	else
		if [ -f "$DEST/$MONTH_YEAR/$DATE.tar" ];then
			msg "Incremental backup already exists [$DEST/$MONTH_YEAR/$DATE.tar], skipping."
			logger -t $NAME "Incremental exists [$DEST/$MONTH_YEAR/$DATE.tar]"
			exit 1
		fi
		msg "Creating incremental backup ..."
		cd $SRC
		tar --exclude={'lost+found','.Trash-1000'} -cpf $DEST/$MONTH_YEAR/$DATE.tar -g $DEST/$MONTH_YEAR/snar *
		echo "$DATE.tar" >> $DEST/$MONTH_YEAR/index
		logger -t $NAME "Created incremental backup [$MONTH_YEAR/$DATE.tar]"
	fi
	echo "Done."
}

function restore_from_backup(){
	msg "Start restoring from backup ..."
	if [ $# -lt "2" ];then
		echo "Error: No arguments given!"
		exit 1
	elif [ $# -gt "2" ];then
		RESTORE_DATE=$(date -d "$2" +'%d-%m-%Y')
		RESTORE_MONTH=$(date -d "$2" +'%b-%Y')
		RESTORE_DIR=$3
	else
		RESTORE_MONTH=$( tail -n 1 $INDEX )
		RESTORE_DIR=$2
	fi
	if [ ! -d "$RESTORE_DIR" ];then
			mkdir -pv $RESTORE_DIR
	fi
	for day in $(cat "$DEST/$RESTORE_MONTH/index"); do
		if [ "$day" == "$RESTORE_DATE.tar" ]; then
			msg "Restoring $day to $RESTORE_DIR ..."
			tar -xf $DEST/$RESTORE_MONTH/$day -g /dev/null -C $RESTORE_DIR
			msg "Backup has been restored!"
			exit 0
		else
			msg "Restoring $day to $RESTORE_DIR ..."
			tar -xf $DEST/$RESTORE_MONTH/$day -g /dev/null -C $RESTORE_DIR
		fi
	done
	exit 0
}


##### Script starts here! #####
if [ "$1" == "--version" ] || [ "$1" == "--help" ]; then
	view_help
	exit 0
elif [ "$1" == "--restore" ]; then
	restore_from_backup $1 $2 $3
	exit 0
elif [ "$1" == "--remove" ]; then
	remove_old_backup
	exit 0
elif [ "$1" == "--source" ]; then
	set_source $2
	exit 0
elif [ "$1" == "--dest" ]; then
	set_dest $2
	exit 0
elif [ "$1" == "--migrate" ]; then
	migrate $2
	exit 0
elif [ "$1" == "--list" ]; then
	list_backups $2
	exit 0
elif [ "$1" == "--log" ]; then
	journalctl -t $NAME
	exit 0
else
	create_backup
	exit 0
fi
