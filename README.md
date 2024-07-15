# Automatic backups

### Description version 7
> [!NOTE]
> This version is not compatible with any previous versions.<br>

This backup script utilizes tar and systemd to create differential backups daily or weekly. The script will continue to make differential backups until the latest backup is 70% of or larger than the first initial backup. When this threshold is reached a new full backup is made. The script will also remove old backups if the --set-limit is lower than (target directory + stored backups). It will also automatically update --set-limit so that it's always two times larger than the target directory as long as there is enough free space.<br>

### Install and setup
Install with **`sudo ./install.sh`** and then run **`sudo bakup --setup`** to configure.<br>

## Whats new (v7.1)
- Added check for file changes before making backup only if needed.<br>
- Added function to find existing backups during setup.<br>
- Added ability to set custom threshold value.<br>
- Added option to use all free space by setting limit to 0.<br>
- Added option to set maximum number of differentials before new full backup.<br>

### Usage
```
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
```
