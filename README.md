# backup version 6!
- Backup directory using tar.<br />
- Run it daily or weekly using systemd timer.<br />
- Creates a new full backup every month and an incremental backup until next month.<br />
- Old backups will be removed if low on space.<br />
- Requires bc command to calculate available space.
- Restore latest backup or choose a date.
- Migrate entire backup directory to new location.

### $ toolbox-backup --help for more info!
