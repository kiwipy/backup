## [Unreleased]

## [7.1.2] - 2024-08-27
### Fixed
- `cleanup_dest()` wrong variable name $CURRENT -> $PREV

## [7.1.1] - 2024-08-25
### Fixed
- `cleanup_dest()` function rewrite.
- `remove_backup()` check file after removed.

### Changed
- All single brackets to double.

## [7.1.0] - 2024-07-15
### Added
- Check for file changes before making backup.
- Find existing backups during setup.
- Custom threshold value.
- Option to use all free space.
- Option to set maximum number of differentials.

## [7.0.2] - 2024-07-09
### Fixed
- install.sh: service files mode set to 644.

## [7.0.1] - 2024-05-30
### Fixed
- journalctl: wrong file name.

## [7.0.0] - 2024-05-29
_Complete rewrite_
### Changed
- **Breaking:** name changed from backup to bakup.
- **Breaking:** new install path.
- **Breaking:** switched from incremental to differential backups.

### Added
- Archive compression.
- New `setup()` function.
- Size limit for stored backups.
- Automate cleanup of old backups.
