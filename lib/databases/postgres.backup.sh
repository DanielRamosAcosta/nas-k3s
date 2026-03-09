#!/bin/bash
set -euo pipefail

BACKUP_DIR="/backups/base"
BACKUP_NAME="backup-$(date +%Y%m%d-%H%M%S)"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

echo "Starting base backup: $BACKUP_NAME"

# Create base backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Perform base backup
pg_basebackup \
  -h postgres.databases.svc.cluster.local \
  -p 5432 \
  -U postgres \
  -D "$BACKUP_PATH" \
  -Ft \
  -z \
  -P \
  -v

echo "Base backup completed: $BACKUP_NAME"

# Create a marker file with backup metadata
cat > "$BACKUP_PATH/backup.info" <<EOF
backup_name=$BACKUP_NAME
backup_date=$(date -Iseconds)
postgres_version=$(psql -h postgres.databases.svc.cluster.local -U postgres -c 'SELECT version();' -t | head -n1)
EOF

echo "Backup metadata saved"
