#!/usr/bin/env bash
set -euo pipefail

# === Config ===
BACKUP_DIR="${BACKUP_DIR:-/var/backups/mysql}"
MYSQL_CNF="${MYSQL_CNF:-$HOME/.my.cnf}"

usage() {
  echo "Usage: $0 [PATH_TO_SQL_OR_GZ]"
  echo "If no file is provided, the newest backup in \$BACKUP_DIR is used."
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage; exit 0
fi

# === Pick backup file ===
backup_file="${1:-}"
if [[ -z "$backup_file" ]]; then
  backup_file="$(ls -1t "$BACKUP_DIR"/all-*.sql.gz 2>/dev/null | head -n1 || true)"
  if [[ -z "$backup_file" ]]; then
    echo "ERROR: No backup files found in $BACKUP_DIR"
    exit 1
  fi
fi

if [[ ! -f "$backup_file" ]]; then
  echo "ERROR: File not found: $backup_file"
  exit 1
fi

if [[ ! -f "$MYSQL_CNF" ]]; then
  echo "ERROR: MySQL client config not found at $MYSQL_CNF"
  exit 1
fi

echo "Restoring from: $backup_file"

# === Confirm (optional, uncomment to ask) ===
# read -p "This will overwrite existing data. Continue? (yes/NO) " ans
# [[ "$ans" == "yes" ]] || { echo "Aborted."; exit 0; }

# === Execute restore ===
if [[ "$backup_file" == *.gz ]]; then
  gunzip -c "$backup_file" | mysql --defaults-file="$MYSQL_CNF"
else
  mysql --defaults-file="$MYSQL_CNF" < "$backup_file"
fi

echo "Restore completed successfully."
