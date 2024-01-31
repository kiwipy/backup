# backup
- Automated backup using rsync or tar.<br />
- Run it daily using cron job.<br />
- Creates a new full backup every sunday and a differential backup every day until next sunday.<br />
    or use incremental backups weekly with tar.<br />
- Old backups will be removed if low on space.<br />
- Requires bc command to calculate available space.

### Restore function does not work with the tar script!
A completely new script will be replacing this repo soon.
