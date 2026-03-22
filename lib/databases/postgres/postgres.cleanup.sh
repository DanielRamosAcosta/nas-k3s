#!/bin/sh
set -e

BACKUP_DIR="/backups/base"
WAL_DIR="/backups/wal_archive"
RETENTION=7

echo "Starting backup cleanup (keeping $RETENTION backups)"

# Count existing backups
BACKUP_COUNT=$(ls -1d $BACKUP_DIR/backup-* 2>/dev/null | wc -l)
echo "Found $BACKUP_COUNT backups"

if [ "$BACKUP_COUNT" -gt "$RETENTION" ]; then
  # Remove oldest backups beyond retention
  TO_DELETE=$((BACKUP_COUNT - RETENTION))
  echo "Removing $TO_DELETE old backups"

  ls -1td $BACKUP_DIR/backup-* | tail -n "$TO_DELETE" | while read backup; do
    echo "Deleting: $backup"
    rm -rf "$backup"
  done

  echo "Base backup cleanup completed"
else
  echo "No base backup cleanup needed (backups: $BACKUP_COUNT, retention: $RETENTION)"
fi

# Clean up WAL segments older than the oldest remaining base backup
OLDEST_BACKUP=$(ls -1d $BACKUP_DIR/backup-* 2>/dev/null | sort | head -n1)
if [ -n "$OLDEST_BACKUP" ] && [ -d "$WAL_DIR" ]; then
  WAL_COUNT_BEFORE=$(ls -1 "$WAL_DIR" | wc -l)
  echo "WAL archive has $WAL_COUNT_BEFORE files"

  # Remove WAL files older than the oldest base backup directory
  echo "Removing WAL segments older than $(basename "$OLDEST_BACKUP")"
  find "$WAL_DIR" -type f ! -newer "$OLDEST_BACKUP" -delete

  WAL_COUNT_AFTER=$(ls -1 "$WAL_DIR" | wc -l)
  WAL_DELETED=$((WAL_COUNT_BEFORE - WAL_COUNT_AFTER))
  echo "Removed $WAL_DELETED WAL files"
else
  echo "Skipping WAL cleanup (no base backups or WAL directory found)"
fi

# Show remaining backups
echo "Current backups:"
ls -lh $BACKUP_DIR/
echo "WAL archive files: $(ls -1 "$WAL_DIR" 2>/dev/null | wc -l)"
