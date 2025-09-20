#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# MySQL backup (Docker container)
# - Reads ALL configuration from an env file.
# - Env file path is changeable via --env-file or ENV_FILE.
# - Default env file path: /root/env/mysql_backup/.env
# - Dumps all databases by default; optional single DB via MYSQL_DATABASE.
# - Uses docker exec to run mysqldump inside the container.
# =========================================================

usage() {
  echo "Usage: $0 [--env-file /path/to/.env]"
}

ENV_FILE_DEFAULT="/root/env/mysql_backup/.env"
ENV_FILE="${ENV_FILE:-$ENV_FILE_DEFAULT}"

if [[ "${1:-}" == "--env-file" && -n "${2:-}" ]]; then
  ENV_FILE="$2"
fi

# === Load required environment file ===
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Required env file not found: $ENV_FILE"
  echo "Default path is $ENV_FILE_DEFAULT (override with --env-file)"
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

# === Config (from env file with sane defaults) ===
DOCKER_CONTAINER="${DOCKER_CONTAINER:?Set DOCKER_CONTAINER in env file}"
MYSQL_USER="${MYSQL_USER:?Set MYSQL_USER in env file}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:?Set MYSQL_PASSWORD in env file}"
MYSQL_DATABASE="${MYSQL_DATABASE:-}"     # if empty => all databases

BACKUP_DIR="${BACKUP_DIR:-/var/backups/mysql}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
BACKUP_BASENAME="${BACKUP_BASENAME:-all-databases}"

# Compute log file default after BACKUP_DIR is finalized
LOG_FILE="${LOG_FILE:-$BACKUP_DIR/backup.log}"

# === Prep ===
timestamp="$(date +'%Y%m%d-%H%M%S')"
mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"

# Sanitize basename to avoid weird filenames
_sanitized_basename="$(printf '%s' "$BACKUP_BASENAME" | tr -cd 'A-Za-z0-9._-')"
if [[ -z "$_sanitized_basename" ]]; then
  _sanitized_basename="all-databases"
fi

echo "[$(date +'%F %T')] Starting MySQL backup (container=$DOCKER_CONTAINER)..." | tee -a "$LOG_FILE"

# === Build dump scope ===
dump_scope=(--all-databases)
if [[ -n "$MYSQL_DATABASE" && "$MYSQL_DATABASE" != "*" ]]; then
  dump_scope=("$MYSQL_DATABASE")
fi

# === Dump via docker exec ===
outfile="$BACKUP_DIR/${_sanitized_basename}-${timestamp}.sql.gz"

if docker exec \
  --env MYSQL_PWD="$MYSQL_PASSWORD" \
  "$DOCKER_CONTAINER" \
  mysqldump \
    -u"$MYSQL_USER" \
    --single-transaction \
    --quick \
    --routines \
    --triggers \
    --events \
    --hex-blob \
    --set-gtid-purged=OFF \
    --skip-lock-tables \
    "${dump_scope[@]}" 2>>"$LOG_FILE" \
  | gzip -c > "$outfile"; then
  :
else
  echo "[$(date +'%F %T')] Backup FAILED (mysqldump/docker exec error)" | tee -a "$LOG_FILE"
  exit 2
fi

# === Verify gzip integrity ===
if gzip -t "$outfile" 2>>"$LOG_FILE"; then
  echo "[$(date +'%F %T')] Backup OK: $outfile" | tee -a "$LOG_FILE"
else
  echo "[$(date +'%F %T')] Backup FAILED (gzip test): $outfile" | tee -a "$LOG_FILE"
  exit 3
fi

# === Retention ===
if [[ "${RETENTION_DAYS:-0}" -gt 0 ]]; then
  find "$BACKUP_DIR" -type f -name "${_sanitized_basename}-*.sql.gz" -mtime +"$RETENTION_DAYS" -print -delete | \
    sed 's/^/[DELETE] /' | tee -a "$LOG_FILE" || true
fi

echo "[$(date +'%F %T')] Finished." | tee -a "$LOG_FILE"

