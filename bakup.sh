#!/bin/bash
#
# Application: Bakup
# Comment:     Automated backups
# Copyright:   William Andersson 2024
# Website:     https://github.com/william-andersson
# License:     GPL  
#
VERSION=7.1.1

if [[ $EUID -ne 0 ]];then
    echo -e "\nThis script must be run as root!"
    exit 1
fi

# Load config file if exists.
if [[ ! -f "/usr/local/etc/bakup.cfg" ]];then
    if [[ "$STARTED_BY_SYSTEMD" != yes ]];then
        if [[ "$1" != "--setup" ]];then
            echo -e "\n*** No config file found, Run --setup first! ***\n"
        fi
    else
        echo "[ERROR] No config file found!"
        exit 1
    fi
else
    source /usr/local/etc/bakup.cfg 2>/dev/null
fi
DATE=$(date +%d-%m-%Y)

view_help(){
cat <<EOF
Usage: bakup <OPTION>
Automated differential backups using tar.

Options:
  --setup                    run initial setup to configure bakup
                               existing backups will be found if using the
                               same directories
  --run                      perform backup now manually
  --list                     list all available backups
  --log                      show log messages from journalctl
  --migrate <PATH>           move entire backup directory to new location
  --restore <DATE> <PATH>    restore from backup where PATH is directory path
                               for extracted archive
  --help                     display this help text
  --version                  print version information

Settings:
  --set-target <PATH>        set or change TARGET directory
  --set-dest <PATH>          set or change DESTINATION directory
  --set-auto <OPTION>        run backup automatically at interval
                               valid options: daily, weekly, off
  --set-thresh <INT>         differential size in % of full backup before
                               a new full backup is be made
                               valid values between 10-99 (default 70)
  --set-limit <INT>          set or change size limit for backup location (GB)
                               if set to 0, use all free space
  --set-max <INT>            set maximum number of differential backups
                               (optional) (default 0)

Bakup at GitHub: <https://github.com/william-andersson/backup>
EOF
}

view_version(){
cat <<EOF
bakup version $VERSION
Copyright (C) 2024 William Andersson.
License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Written by William Andersson.
EOF
}

update_config(){
    echo "TARGET=${TARGET%/}" > /usr/local/etc/bakup.cfg
    echo "DEST=${DEST%/}" >> /usr/local/etc/bakup.cfg
    echo "LIMIT=$LIMIT" >> /usr/local/etc/bakup.cfg
    echo "TIMER=$TIMER" >> /usr/local/etc/bakup.cfg
    echo "PREV=$PREV" >> /usr/local/etc/bakup.cfg
    echo "CURRENT=$CURRENT" >> /usr/local/etc/bakup.cfg
    echo "THRESH=$THRESH" >> /usr/local/etc/bakup.cfg
    echo "MAX=$MAX" >> /usr/local/etc/bakup.cfg
    echo "HASH=$HASH" >> /usr/local/etc/bakup.cfg
}

setup(){
    read -e -p "Target path: " TARGET
    read -e -p "Destination: " DEST
    read -p "Backup limit (GB): " LIMIT
    read -p "Autorun (daily/weekly/off): " TIMER

    set_path "--set-target" $TARGET
    set_path "--set-dest" $DEST
    set_limit $LIMIT
    auto_timer $TIMER
    set_thresh 70
    set_max 0

    HASH=""

    if [[ ! -d "/usr/local/etc" ]];then
        mkdir -p /usr/local/etc
    fi
    touch /usr/local/etc/bakup.cfg
    chmod 755 /usr/local/etc/bakup.cfg

    search_for_backups
    update_config
    exit 0
}

search_for_backups(){
    #
    # Look for existing backups to use as starting point
    #
    if [[ $(ls -l $DEST | grep index | wc -l) -eq 1 ]];then
        CURRENT=$(ls -t $DEST | grep -m 1 index | cut -f1 -d".")
        PREV=$CURRENT
        echo "Found existing backup. Added: [$CURRENT]"
    elif [[ $(ls -l $DEST | grep index | wc -l) -eq 2 ]];then
        CURRENT=$(ls -t $DEST | grep -m 1 index | cut -f1 -d".")
        PREV=$(ls -tr $DEST | grep -m 1 index | cut -f1 -d".")
        echo "Found existing backups. Added: [$CURRENT] and [$PREV]"
    else
        PREV=""
        CURRENT=""
    fi
}

auto_timer(){
    local NEW_TIMER=$1
    local current_timer=$(cat /etc/systemd/system/bakup-auto.timer | grep OnCalendar)
    if [[ "$NEW_TIMER" == "off" ]];then
        sed -i 's:'$current_timer':'OnCalendar=$NEW_TIMER':' /etc/systemd/system/bakup-auto.timer
        systemctl disable bakup-auto.timer --now 2>/dev/null
        echo "auto timer set: [$NEW_TIMER]"
        TIMER=$NEW_TIMER
    else
        sed -i 's:'$current_timer':'OnCalendar=$NEW_TIMER':' /etc/systemd/system/bakup-auto.timer
        (sleep 5; systemctl enable bakup-auto.timer --now 2>/dev/null) &
        echo "auto timer set: [$NEW_TIMER]"
        TIMER=$NEW_TIMER
    fi
}

set_limit(){
    if ! [[ $1 =~ ^[0-9]+$ ]];then
        echo "Input value not integer!"
        exit 1
    fi
    if [[ "$1" == "0" ]];then
        LIMIT=0
    else
        LIMIT=$(($(($1*1024))*1024))
    fi
}

set_thresh(){
    if ! [[ $1 =~ ^[0-9]+$ ]];then
        echo "Input value not integer!"
        exit 1
    fi
    if [[ $1 -ge 10 ]] && [[ $1 -lt 100 ]];then
        THRESH=$1
    else
        echo "Invalid thresh value (10-99)"
        exit 1
    fi
}

set_max(){
    if ! [[ $1 =~ ^[0-9]+$ ]];then
        echo "Input value not integer!"
        exit 1
    fi
    MAX=$1
}

set_path(){
    # Called by --set-target, --set-dest & --migrate
    if [[ ! $2 ]];then
        echo "Missing path!"
        exit 2
    fi
    
    if [[ "$1" == "--set-target" ]];then
        TARGET=$2
        if [[ ! -d "$TARGET" ]];then
            echo "No such directory! [$TARGET]"
            exit 2
        else
            echo "Target directory set [$TARGET]"
        fi
    elif [[ "$1" == "--set-dest" ]];then
        DEST=$2
        if [[ ! -d "$DEST" ]];then
            mkdir -pv $DEST
        fi
        echo "Destination directory set [$DEST]"
    elif [[ "$1" == "--migrate" ]];then
        mkdir -pv ${2%/}
        mv -v $DEST/* -t ${2%/}/
        if [[ "$?" == "0" ]];then
            rm -rv $DEST
            DEST=$2
            echo "Backup directory migrated to [$DEST]"
        else
            echo "There was an error during the migration!"
            exit 1
        fi
    fi
}

list_backups(){
    echo "### Available backups ###"
    echo "$PREV - $(du -sh $DEST/$PREV.tgz | awk '{print $1}') *"
    for bak in $(cat $DEST/$PREV.index);do
        echo "$bak - $(du -sh $DEST/$bak.tgz | awk '{print $1}')"
    done
    if [[ "$PREV" != "$CURRENT" ]];then
        echo "$CURRENT - $(du -sh $DEST/$CURRENT.tgz | awk '{print $1}') *"
        for bak in $(cat $DEST/$CURRENT.index);do
            echo "$bak - $(du -sh $DEST/$bak.tgz | awk '{print $1}')"
        done
    fi
}

remove_backup(){
    #
    # Remove the oldest backup from PREV first and finally
    # the main previous backup when index file is empty.
    #
    local OLD=$(awk 'NR==1{print}' $DEST/$PREV.index)
    if [[ ! -z "$OLD" ]];then
        rm $DEST/$OLD.*
        if [[ ! -f "$DEST/$OLD.tgz" ]];then
            echo "Removed backup [$OLD]"
            echo "Updating index file"
            sed -i '1d' $DEST/$PREV.index
        else
            echo "Could not remove [$OLD]"
        fi
    fi
    local OLD=$(awk 'NR==1{print}' $DEST/$PREV.index)
    if [[ -z "$OLD" ]];then
        rm $DEST/$PREV.*
        if [[ ! -f "$DEST/$PREV.tgz" ]];then
            echo "Removed backup [$PREV]*"
            PREV=$CURRENT
            update_config
        else
            echo "Could not remove [$PREV]*"
        fi
    fi
}

cleanup_dest(){
    # Remove all old backups that are not present in CURRENT or PREV
    echo "Cleaning up $DEST"
    for tgz in $(ls $DEST | grep .tgz);do
        if [[ ! -f "$DEST/$CURRENT.index" ]] || [[ ! -f "$DEST/$CURRENT.index" ]];then
            echo "Missing index file; cleanup aborted!"
            break
        fi
        if [[ $(cat $DEST/$CURRENT.index) != *${tgz%.*}* ]] && [[ "$tgz" != "$CURRENT.tgz" ]];then
            if [[ $(cat $DEST/$PREV.index) != *${tgz%.*}* ]] && [[ "$tgz" != "$PREV.tgz" ]];then
                rm $DEST/${tgz%.*}.*
                if [[ ! -f "$DEST/$tgz" ]];then
                    echo "Removed old backup [$tgz]"
                else
                    echo "Could not remove old backup [$tgz]"
                fi
            fi
        fi
    done
    echo "Done."
}

calc_space(){
    #
    # Make sure limit is always 2x larger than target if not set to 0,
    # as long as disk space allows.
    #
    cleanup_dest
    local TARGET_SIZE=$(du -s --block-size=1K $TARGET | awk '{print $1}')
    if [[ $(($TARGET_SIZE*2)) -gt $LIMIT ]];then
        local FREE_SPACE=$(df --block-size=1K $DEST | awk '/\// {print $4}')
        if [[ $(($TARGET_SIZE*2)) -lt $FREE_SPACE ]];then
            if [[ "$LIMIT" != "0" ]];then
                # Format output as human readable.
                local NEW_LIMIT_GB=$(($(($(($TARGET_SIZE*2))/1024))/1024))
                local NEW_LIMIT_MB=$(($(($TARGET_SIZE*2))/1024))
                local NEW_LIMIT_KB=$(($TARGET_SIZE*2))
                if [[ $NEW_LIMIT_GB -ge 10 ]];then
                    local NEW_LIMIT=$NEW_LIMIT_GB"GB"
                elif [[ $NEW_LIMIT_MB -ge 10 ]];then
                    local NEW_LIMIT=$NEW_LIMIT_MB"MB"
                else
                    local NEW_LIMIT=$NEW_LIMIT_KB"KB"
                fi
                echo "Updating limit to [$NEW_LIMIT]"
                LIMIT=$(($TARGET_SIZE*2))
                update_config
            else
                echo "Limit set to free space."
            fi
        else
            echo "[WARNING] Low disk space; backup history might be limited!"
            local TEN=$(($(($TARGET_SIZE/100))*10))
            local MAX=$(($TARGET_SIZE+$TEN))
            if [[ $FREE_SPACE -le $MAX ]];then
                echo "[CRITICAL] Disk space margin less than 10%; consider migrate backups!"
            elif [[ $FREE_SPACE -lt $TARGET_SIZE ]];then
                echo "[FAILED] Not enough disk space; exiting!"
                exit 1
            fi
        fi
    fi

    #
    # Remove old backups if limit is reached or if not enough free space
    # when limit is set to 0.
    # Continue removing until space is sufficient.
    #
    while true;do
        local BACKUP_SIZE=$(du -s --block-size=1K $DEST | awk '{print $1}')
        local REQUIRED_SPACE=$(($BACKUP_SIZE+$TARGET_SIZE))
        if [[ "$LIMIT" != "0" ]] && [[ $REQUIRED_SPACE -gt $LIMIT ]];then
            remove_backup
        elif [[ "$LIMIT" == "0" ]] && [[ $REQUIRED_SPACE -ge $FREE_SPACE ]];then
            remove_backup
        else
            echo "Sufficient free space."
            break
        fi
    done
}

get_thresh(){
    #
    # If MAX is set and reached, create new full backup OR
    # if MAX is set to 0 and latest differential backup exceeds
    # THRESH (default 70%) of the original full backup then
    # create a new full backup.
    #
    if [[ -z "$THRESH" ]];then
        set_thresh 70
        update_config
    fi
    if [[ -z "$MAX" ]];then
        set_max 0
        update_config
    fi
    if [[ -f "$DEST/$CURRENT.index" ]];then
        local LAST_BACKUP=$(cat $DEST/$CURRENT.index | tail -1)
        if [[ ! -z "$LAST_BACKUP" ]];then
            local LAST_BACKUP_SIZE=$(du -s --block-size=1K $DEST/$LAST_BACKUP.tgz | awk '{print $1}')
            local LAST_FULL_SIZE=$(du -s --block-size=1K $DEST/$CURRENT.tgz | awk '{print $1}')
            local THRESH_VAL=$(($(($LAST_FULL_SIZE*$THRESH))/100))
            if [[ "$MAX" != "0" ]] && [[ $(wc -l < "$DEST/$CURRENT.index") -ge $MAX ]];then
                echo "MAX value ($MAX) reached."
                NEW_FULL=1
            elif [[ $LAST_BACKUP_SIZE -ge $THRESH_VAL ]];then
                echo "THRESH value ($THRESH%) reached."
                NEW_FULL=1
            else
                NEW_FULL=0
            fi
        else
            NEW_FULL=0
        fi
    else
        NEW_FULL=1
    fi
}

files_changed(){
    #
    # Check if files has changed since previous backup.
    # If not, no backup is needed.
    #
    STATE=$(find $TARGET -type f -exec md5sum {} + | LC_ALL=C sort | md5sum | awk '{print $1}')
    if [[ ! -z "$HASH" ]] && [[ "$STATE" == "$HASH" ]];then
        echo "Hash match, nothing to backup."
        exit 0
    else
        HASH=$STATE
        update_config
    fi
}

create_backup(){
    if [[ ! -d "$TARGET" ]];then
        echo "No target directory!"
        exit 1
    elif [[ ! -d "$DEST" ]];then
        mkdir -pv $DEST
    fi
    if [[ -z "$CURRENT" ]];then
        CURRENT=$DATE
    fi
    if [[ -f "$DEST/$DATE.tgz" ]];then
        echo "Backup [$DATE.tgz] already exists."
        exit 0
    fi

    files_changed
    calc_space
    get_thresh

    if [[ $NEW_FULL == "1" ]];then
        PREV=$CURRENT
        CURRENT=$DATE
        echo "Creating full backup [$DEST/$CURRENT.tgz]"
        tar --exclude-from=/usr/local/share/bakup/exclude -cpzf $DEST/$CURRENT.tgz -g $DEST/$CURRENT.snar -C $TARGET .
        touch $DEST/$CURRENT.index
        update_config
        exit 0
    else
        cp $DEST/$CURRENT.snar $DEST/$DATE.snar
        echo "Creating diff backup [$DEST/$DATE.tgz]"
        tar --exclude-from=/usr/local/share/bakup/exclude -cpzf $DEST/$DATE.tgz -g $DEST/$DATE.snar -C $TARGET .
        echo "Updating index file"
        echo $DATE >> $DEST/$CURRENT.index
        exit 0
    fi
}

restore_from_backup(){
    if [[ "$#" -lt 2 ]];then
        echo "Error: missing argument!"
        exit 2
    else
        RESTORE_DATE=$1
        RESTORE_DIR=$2
    fi
    if [[ ! -d "$RESTORE_DIR" ]];then
        mkdir -pv $RESTORE_DIR
    fi
    
    if [[ "$RESTORE_DATE" == "$PREV" ]] || $(grep -Fxq "$RESTORE_DATE" $DEST/$PREV.index);then
        echo "Unpacking $PREV ..."
        tar -xf $DEST/$PREV.tgz -g /dev/null -C $RESTORE_DIR
        if [[ "$RESTORE_DATE" != "$PREV" ]];then
            echo "Restoring from backup $RESTORE_DATE ..."
            tar -xf $DEST/$RESTORE_DATE.tgz -g /dev/null -C $RESTORE_DIR
        fi
    elif [[ "$RESTORE_DATE" == "$CURRENT" ]] || $(grep -Fxq "$RESTORE_DATE" $DEST/$CURRENT.index);then
        echo "Unpacking $CURRENT ..."
        tar -xf $DEST/$CURRENT.tgz -g /dev/null -C $RESTORE_DIR
        if [[ "$RESTORE_DATE" != "$CURRENT" ]];then
            echo "Restoring from backup $RESTORE_DATE ..."
            tar -xf $DEST/$RESTORE_DATE.tgz -g /dev/null -C $RESTORE_DIR
        fi
    else
        echo "No such backup! [$DEST/$RESTORE_DATE]"
        exit 1
    fi
    chown $(id -u $SUDO_USER):$(id -g $SUDO_USER) $RESTORE_DIR
    echo "Backup has been restored!"
    exit 0
}

if [[ "$#" -gt 3 ]] && [[ "$1" == "--restore" ]] || [[ "$#" -gt 2 ]];then
    echo "To many arguments."
    exit 1
fi

case $1 in
    --setup)
        setup
        ;;
    --run)
        create_backup
        ;;
    --list)
        list_backups
        ;;
    --log)
        journalctl -e -u bakup-auto
        ;;
    --restore)
        restore_from_backup $2 $3
        ;;
    --help)
        view_help
        exit 0
        ;;
    --version)
        view_version
        exit 0
        ;;
    --set-target|--set-dest|--migrate)
        set_path $1 $2
        update_config
        ;;
    --set-limit)
        set_limit $2
        update_config
        ;;
    --set-auto)
        auto_timer $2
        update_config
        ;;
    --set-thresh)
        set_thresh $2
        update_config
        ;;
    --set-max)
        set_max $2
        update_config
        ;;
    *)
        view_help
        exit 0
        ;;
esac
