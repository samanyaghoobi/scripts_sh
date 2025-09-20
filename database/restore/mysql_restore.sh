#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# MySQL restore (Docker container)
# - Reads ALL configuration from an env file.
# - Env file path is changeable via --env-file or ENV_FILE.
# - Default env file path: /root/env/mysql_backup/.env
# - If no backup file is given, uses newest in BACKUP_DIR.
# - Supports .sql and .sql.gz files.
# - Uses docker exec to run mysql inside the container.
# - Extras:
#   * --showdb prints databases contained in a backup without restoring
#   * --file PATH selects a specific backup file
# =========================================================

usage() {
  echo "Usage: $0 [--env-file /path/to/.env] [--showdb] [--file PATH_TO_SQL_OR_GZ] [PATH_TO_SQL_OR_GZ]"
  echo "Examples:"
  echo "  $0 --showdb                       # show DBs from newest backup"
  echo "  $0 --file /path/backup.sql.gz --showdb"
  echo "  $0 /path/backup.sql.gz            # restore specific file"
}

ENV_FILE_DEFAULT="/root/env/mysql_backup/.env"
ENV_FILE="${ENV_FILE:-$ENV_FILE_DEFAULT}"

want_showdb=0
arg_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"; shift 2 ;;
    --showdb)
      want_showdb=1; shift ;;
    --file)
      arg_file="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      # treat as positional file if not set already
      if [[ -z "$arg_file" ]]; then arg_file="$1"; fi
      shift ;;
  esac
done

# === Load env ===
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Required env file not found: $ENV_FILE"
  echo "Default path is $ENV_FILE_DEFAULT (override with --env-file)"
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

# === Config ===
DOCKER_CONTAINER="${DOCKER_CONTAINER:?Set DOCKER_CONTAINER in env file}"
MYSQL_USER="${MYSQL_USER:?Set MYSQL_USER in env file}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:?Set MYSQL_PASSWORD in env file}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/mysql}"
BACKUP_BASENAME="${BACKUP_BASENAME:-all-databases}"
LOG_FILE="${LOG_FILE:-$BACKUP_DIR/backup.log}"

mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"

# === Pick backup file ===
backup_file="$arg_file"
if [[ -z "$backup_file" ]]; then
  backup_file="$(ls -1t "$BACKUP_DIR"/"${BACKUP_BASENAME}"-*.sql*.gz "$BACKUP_DIR"/"${BACKUP_BASENAME}"-*.sql 2>/dev/null | head -n1 || true)"
  if [[ -z "$backup_file" ]]; then
    echo "[$(date +'%F %T')] ERROR: No backup files found in $BACKUP_DIR" | tee -a "$LOG_FILE"
    exit 1
  fi
fi

if [[ ! -f "$backup_file" ]]; then
  echo "[$(date +'%F %T')] ERROR: File not found: $backup_file" | tee -a "$LOG_FILE"
  exit 1
fi

if [[ $want_showdb -eq 1 ]]; then
  # Print database names contained in the dump without restoring
  if [[ "$backup_file" == *.gz ]]; then
    reader=(gzip -dc "$backup_file")
  else
    reader=(cat "$backup_file")
  fi

  "${reader[@]}" |
  awk '
    /^-- Current Database:/ {
      if (match($0,/`([^`]*)`/,m)) { db[m[1]]=1 }
      else if (match($0,/:[[:space:]]*([^[:space:]]+)/,m)) { db[m[1]]=1 }
    }
    /^CREATE (DATABASE|SCHEMA)/ {
      if (match($0,/`([^`]*)`/,m)) { db[m[1]]=1 }
    }
    /^USE / {
      if (match($0,/`([^`]*)`/,m)) { db[m[1]]=1 }
    }
    END { for (d in db) print d }
  ' | sort
  exit 0
fi

echo "[$(date +'%F %T')] Starting restore (container=$DOCKER_CONTAINER) from: $backup_file" | tee -a "$LOG_FILE"

# === Execute restore ===
set +e
if [[ "$backup_file" == *.gz ]]; then
  if gunzip -c "$backup_file" | docker exec -i --env MYSQL_PWD="$MYSQL_PASSWORD" "$DOCKER_CONTAINER" mysql -u"$MYSQL_USER" 2>>"$LOG_FILE"; then
    rc=0
  else
    rc=$?
  fi
else
  if cat "$backup_file" | docker exec -i --env MYSQL_PWD="$MYSQL_PASSWORD" "$DOCKER_CONTAINER" mysql -u"$MYSQL_USER" 2>>"$LOG_FILE"; then
    rc=0
  else
    rc=$?
  fi
fi
set -e

if [[ $rc -eq 0 ]]; then
  echo "[$(date +'%F %T')] Restore OK: $backup_file" | tee -a "$LOG_FILE"
else
  echo "[$(date +'%F %T')] Restore FAILED (exit=$rc): $backup_file" | tee -a "$LOG_FILE"
  exit $rc
fi
