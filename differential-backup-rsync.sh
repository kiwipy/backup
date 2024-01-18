#!/bin/bash
VERSION=3.4

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

msg(){
	# function to echo message with delay
	echo $1
	sleep 1
}
msg "$0 VERSION=$VERSION"

TARGET="PATH TO WHAT DIR TO BACKUP HERE"
DEST="PATH TO WHERE TO PUT BACKUP HERE"
INDEX="$DEST/index"
LOG="$DEST/backup.log"
TIMESTAMP=$(date +%d-%m-%Y)
INT_DAY=$(date +%u)
DAY=$(date +%a)
WEEK=$(date +%W-%Y)

msg "Calculating required space ..."
TMP=$(du -sh $TARGET/ | awk '{print $1}' | sed 's/.$//')
REQ=$(echo "$TMP*1.1" | bc | sed 's/..$//') #add 10% margin
msg "[$REQ]"

while true; do	
	msg "Calculating available space ..."
	AVA=$(df -h | awk -v pat="$DEST" '$0~pat{print $4}' | sed 's/.$//')
	msg "[$AVA]"
	if [ $AVA -le $REQ ]; then
		OLD=$(awk 'NR==1{print}' $INDEX)
		if [ -d "$DEST/$OLD" ]; then
			msg "Removing old backup [$OLD] ..."
			rm -r $DEST/$OLD
			echo "$TIMESTAMP: *** Removed old backup [$OLD] ***" >> $LOG
		fi
		msg "Updating index file ..."
		sed -i '1d' $INDEX
	else
		msg "Sufficient free space."
		break
	fi
done

full_backup(){
	msg "Creating directory [$DEST/$WEEK]"
	mkdir $DEST/$WEEK
	msg "Creating full backup ..."
	rsync -avh --exclude={'lost+found','.Trash-1000'} $TARGET/ $DEST/$WEEK/Mon/
	echo "$TIMESTAMP: Created new full backup [$WEEK]" >> $LOG
	msg "Updating index file ..."
	echo $WEEK >> $INDEX
}

diff_backup(){
	if [ ! -d "$DEST/$WEEK" ]; then
		full_backup
	else
		msg "Creating differential backup ..."
		rsync -avh --exclude={'lost+found','.Trash-1000'} --compare-dest=$DEST/$WEEK/Mon/ $TARGET/ $DEST/$WEEK/$DAY/
		echo "$TIMESTAMP: Created differential backup [$WEEK/$DAY]" >> $LOG
	fi
}


if [ $INT_DAY -lt "02" ]; then
	full_backup
else
	diff_backup
fi
