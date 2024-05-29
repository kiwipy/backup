# Automatic backups

### Description version 7
> [!NOTE]
> This version is not compatible with any previous versions.<br>

This backup script utilizes tar and systemd to create differential backups daily or weekly. The script will continue to make differential backups until the latest backup is 70% of or larger than the first initial backup. When this threshold is reached a new full backup is made. The script will also remove old backups if the --set-limit is lower than (target directory + stored backups). It will also automatically update --set-limit so that it's always two times larger than the target directory as long as there is enough free space.<br>

### Install and setup
Install with **`sudo ./install.sh`** and then run **`sudo backup --setup`** to configure.<br>

### Usage
```
Options:
--setup                        Run initial setup.
--run                          Run backup manually.
--list                         List available backups.
--log                          Show log messages.
--migrate <PATH>               Move entire backup directory.
--restore [DATE] <PATH>        Restore from backup.
--help                         Display this text.

Settings:
--set-target <PATH>            Change TARGET directory.
--set-dest <PATH>              Change DESTINATION directory.
--set-limit <INT>              Change size limit for backup location (GB).
--set-auto <OPTION>            OPTIONS: daily, weekly, off
```
