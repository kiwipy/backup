#!/bin/bash
#
# Application: Bakup
# Comment:     Automated backups
# Copyright:   William Andersson 2024
# Website:     https://github.com/william-andersson
# License:     GPL  
#
VERSION=7.0.0

if [[ $EUID -ne 0 ]]; then
    echo -e "\nThis script must be run as root!"
    exit 1
fi

# Load config file if exists.
if [ ! -f "/usr/local/etc/bakup.cfg" ];then
    if [ "$STARTED_BY_SYSTEMD" != yes ]; then
        if [ "$1" != "--setup" ];then
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
Bakup $VERSION (Automated backups)
Usage: $0 <OPTION>

Options:
--setup                        Run initial setup.
--run                          Run backup manually.
--list                         List available backups
--log                          Show log messages.
--migrate <PATH>               Move entire backup directory.
--restore [DATE] <PATH>        Restore from backup
--help                         Display this text.

Settings:
--set-target <PATH>            Change TARGET directory.
--set-dest <PATH>              Change DESTINATION directory.
--set-limit <INT>              Change size limit for backup location (GB).
--set-auto <OPTION>            OPTIONS: daily, weekly, off
EOF
}

update_config(){
    echo "TARGET=${TARGET%/}" > /usr/local/etc/bakup.cfg
    echo "DEST=${DEST%/}" >> /usr/local/etc/bakup.cfg
    echo "LIMIT=$LIMIT" >> /usr/local/etc/bakup.cfg
    echo "TIMER=$TIMER" >> /usr/local/etc/bakup.cfg
    echo "PREV=$PREV" >> /usr/local/etc/bakup.cfg
    echo "CURRENT=$CURRENT" >> /usr/local/etc/bakup.cfg
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
    
    PREV=""
    CURRENT=""

    if [ ! -d "/usr/local/etc" ];then
        mkdir -pv /usr/local/etc
    fi
    touch /usr/local/etc/bakup.cfg
    chmod -v 755 /usr/local/etc/bakup.cfg

    update_config
    exit 0
}

auto_timer(){
    local NEW_TIMER=$1
    local current_timer=$(cat /etc/systemd/system/bakup-auto.timer | grep OnCalendar)
    if [ "$NEW_TIMER" == "off" ];then
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
    LIMIT=$(($(($1*1024))*1024))
}

set_path(){
    # Called by --set-target, --set-dest & --migrate
    if [ ! $2 ];then
        echo "Missing path!"
        exit 2
    fi
    
    if [ "$1" == "--set-target" ];then
        TARGET=$2
        if [ ! -d "$TARGET" ];then
            echo "No such directory! [$TARGET]"
            exit 2
        else
            echo "Target directory changed [$TARGET]"
        fi
    elif [ "$1" == "--set-dest" ];then
        DEST=$2
        if [ ! -d "$DEST" ];then
            mkdir -pv $DEST
        fi
        echo "Destination directory changed [$DEST]"
    elif [ "$1" == "--migrate" ];then
        mkdir -pv ${2%/}
        mv -v $DEST/* -t ${2%/}/
        rm -rv $DEST
        DEST=$2
        echo "Backup directory migrated to [$DEST]"
    fi
}

list_backups(){
    echo "### Available backups ###"
    echo "$PREV - $(du -sh $DEST/$PREV.tgz | awk '{print $1}') *"
    for bak in $(cat $DEST/$PREV.index); do
        echo "$bak - $(du -sh $DEST/$bak.tgz | awk '{print $1}')"
    done
    if [ "$PREV" != "$CURRENT" ];then
        echo "$CURRENT - $(du -sh $DEST/$CURRENT.tgz | awk '{print $1}') *"
        for bak in $(cat $DEST/$CURRENT.index); do
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
    if [ ! -z "$OLD" ];then
        rm $DEST/$OLD.tgz
        rm $DEST/$OLD.snar
        echo "Removed old backup [$OLD]"
        echo "Updating index file"
        sed -i '1d' $DEST/$PREV.index
    fi
    local OLD=$(awk 'NR==1{print}' $DEST/$PREV.index)
    if [ -z "$OLD" ];then
        rm $DEST/$PREV.tgz
        rm $DEST/$PREV.snar
        rm $DEST/$PREV.index
        echo "Removed old backup [$PREV]"
        PREV=$CURRENT
        update_config
    fi
}

cleanup_dest(){
    # Remove all old backups that are not present in CURRENT or PREV
    for index in $(ls $DEST | grep .index);do
        if [ "$index" != "$CURRENT.index" ] && [ "$index" != "$PREV.index" ];then
            local NAME=${index%.*}
            echo "Cleaning up $DEST - [$NAME]"
            for file in $(cat $DEST/$index);do
                rm $DEST/$file*
            done
            rm $DEST/$NAME*
        fi
    done
}

calc_space(){
    #
    # Make sure limit is always 2x larger than target,
    # as long as disk space allows.
    #
    cleanup_dest
    local TARGET_SIZE=$(du -s --block-size=1K $TARGET | awk '{print $1}')
    if [ $(($TARGET_SIZE*2)) -gt $LIMIT ];then
        local FREE_SPACE=$(df --block-size=1K $DEST | awk '/\// {print $4}')
        if [ $(($TARGET_SIZE*2)) -lt $FREE_SPACE ];then
        
            # Format output as human readable.
            local NEW_LIMIT_GB=$(($(($(($TARGET_SIZE*2))/1024))/1024))
            local NEW_LIMIT_MB=$(($(($TARGET_SIZE*2))/1024))
            local NEW_LIMIT_KB=$(($TARGET_SIZE*2))
            if [ $NEW_LIMIT_GB -ge 10 ];then
                local NEW_LIMIT=$NEW_LIMIT_GB"GB"
            elif [ $NEW_LIMIT_MB -ge 10 ];then
                local NEW_LIMIT=$NEW_LIMIT_MB"MB"
            else
                local NEW_LIMIT=$NEW_LIMIT_KB"KB"
            fi
            echo "Updating limit to [$NEW_LIMIT]"
            LIMIT=$(($TARGET_SIZE*2))
            update_config
        else
            echo "[WARNING] Low disk space; backup history might be limited!"
            local TEN=$(($(($TARGET_SIZE/100))*10))
            local MAX=$(($TARGET_SIZE+$TEN))
            if [ $FREE_SPACE -le $MAX  ];then
                echo "[CRITICAL] Disk space margin less than 10%; consider migrate backups!"
            elif [ $FREE_SPACE -lt $TARGET_SIZE ];then
                echo "[FAILED] Not enough disk space; exiting!"
                exit 1
            fi
        fi
    fi

    #
    # Remove old backups if limit is reached.
    # Continue removing until space is sufficient.
    #
    while true; do
        local BACKUP_SIZE=$(du -s --block-size=1K $DEST | awk '{print $1}')
        local REQUIRED_SPACE=$(($BACKUP_SIZE+$TARGET_SIZE))
        if [ $REQUIRED_SPACE -gt $LIMIT ];then
            remove_backup
        else
            echo "Sufficient free space."
            break
        fi
    done
}

get_thresh(){
    #
    # If latest differential backup exceeds 70% of the original full backup,
    # create a new full backup.
    #
    if [ -f "$DEST/$CURRENT.index" ];then
        local LAST_BACKUP=$(cat $DEST/$CURRENT.index | tail -1)
        if [ ! -z "$LAST_BACKUP" ];then
            local LAST_BACKUP_SIZE=$(du -s --block-size=1K $DEST/$LAST_BACKUP.tgz | awk '{print $1}')
            local LAST_FULL_SIZE=$(du -s --block-size=1K $DEST/$CURRENT.tgz | awk '{print $1}')
            local THRESH=$(($(($LAST_FULL_SIZE*70))/100))
            if [ $LAST_BACKUP_SIZE -gt $THRESH ];then
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

create_backup(){
    if [ ! -d "$TARGET" ];then
        echo "No target directory!"
        exit 1
    elif [ ! -d "$DEST" ];then
        mkdir -pv $DEST
    fi    
    if [ -z "$CURRENT" ];then
        CURRENT=$DATE
    fi
    if [ -f "$DEST/$DATE.tgz" ];then
        echo "Backup [$DATE.tgz] already exists."
        exit 0
    fi

    calc_space
    get_thresh

    if [ $NEW_FULL == "1" ];then
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
    if [ $# -lt "2" ];then
        echo "Error: missing argument!"
        exit 2
    else
        RESTORE_DATE=$1
        RESTORE_DIR=$2
    fi
    if [ ! -d "$RESTORE_DIR" ];then
        mkdir -pv $RESTORE_DIR
    fi
    
    if [ "$RESTORE_DATE" == "$PREV" ] || $(grep -Fxq "$RESTORE_DATE" $DEST/$PREV.index);then
        echo "Unpacking $PREV ..."
        tar -xf $DEST/$PREV.tgz -g /dev/null -C $RESTORE_DIR
        if [ "$RESTORE_DATE" != "$PREV" ];then
            echo "Restoring from backup $RESTORE_DATE ..."
            tar -xf $DEST/$RESTORE_DATE.tgz -g /dev/null -C $RESTORE_DIR
        fi
    elif [ "$RESTORE_DATE" == "$CURRENT" ] || $(grep -Fxq "$RESTORE_DATE" $DEST/$CURRENT.index);then
        echo "Unpacking $CURRENT ..."
        tar -xf $DEST/$CURRENT.tgz -g /dev/null -C $RESTORE_DIR
        if [ "$RESTORE_DATE" != "$CURRENT" ];then
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
        journalctl -e -t backup
        ;;
    --restore)
        restore_from_backup $2 $3
        ;;
    --help)
        view_help
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
    *)
        view_help
        ;;
esac
