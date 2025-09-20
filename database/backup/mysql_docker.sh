#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# MySQL backup script (full: all databases, data + schema)
#
# Required MySQL client config (mysql_conf = ~/.my.cnf by default):
#   File: ~/.my.cnf
#   Permissions: chmod 600 ~/.my.cnf
#   Section: [client]
#   Required keys:
#     user = <backup_user>            # MySQL username
#     password = <STRONG_PASSWORD>    # MySQL password
#   Recommended keys:
#     host = 127.0.0.1                # or your server host
#     port = 3306                     # default port
#   Optional keys (use if needed):
#     socket = /var/run/mysqld/mysqld.sock
#     default-character-set = utf8mb4
#     ssl-mode = REQUIRED             # if you enforce TLS
#     ssl-ca = /path/to/ca.pem
#     ssl-cert = /path/to/client-cert.pem
#     ssl-key = /path/to/client-key.pem
# =========================================================

# === Config (override via environment) ===
BACKUP_DIR="${BACKUP_DIR:-/var/backups/mysql}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
MYSQL_CNF="${MYSQL_CNF:-$HOME/.my.cnf}"   # mysql_conf path
LOG_FILE="${LOG_FILE:-$BACKUP_DIR/backup.log}"

# New: base name for backup files. Safe characters only (A-Za-z0-9._-)
# Examples:
#   BACKUP_BASENAME="prod-full"
#   BACKUP_BASENAME="all-databases"
BACKUP_BASENAME="${BACKUP_BASENAME:-all-databases}"

# === Prep ===
timestamp="$(date +'%Y%m%d-%H%M%S')"
mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"

# Sanitize basename to avoid weird filenames
_sanitized_basename="$(printf '%s' "$BACKUP_BASENAME" | tr -cd 'A-Za-z0-9._-')"
if [[ -z "$_sanitized_basename" ]]; then
  _sanitized_basename="all-databases"
fi

echo "[$(date +'%F %T')] Starting MySQL backup..." | tee -a "$LOG_FILE"

# === Sanity checks ===
if [[ ! -f "$MYSQL_CNF" ]]; then
  echo "ERROR: MySQL client config not found at $MYSQL_CNF" | tee -a "$LOG_FILE"
  exit 1
fi

# === Dump all databases ===
outfile="$BACKUP_DIR/${_sanitized_basename}-${timestamp}.sql.gz"

# Notes:
# --single-transaction for InnoDB consistency (non-blocking)
# --routines, --triggers, --events to include everything
# --hex-blob preserves binary columns
# --set-gtid-purged=OFF avoids issues on replicas when not needed
# --skip-lock-tables to reduce blocking (MyISAM not fully safe)
mysqldump \
  --defaults-file="$MYSQL_CNF" \
  --all-databases \
  --single-transaction \
  --quick \
  --routines \
  --triggers \
  --events \
  --hex-blob \
  --set-gtid-purged=OFF \
  --skip-lock-tables \
  2>>"$LOG_FILE" \
| gzip -c > "$outfile"

# === Verify gzip integrity ===
if gzip -t "$outfile" 2>>"$LOG_FILE"; then
  echo "[$(date +'%F %T')] Backup OK: $outfile" | tee -a "$LOG_FILE"
else
  echo "[$(date +'%F %T')] Backup FAILED (gzip test): $outfile" | tee -a "$LOG_FILE"
  exit 2
fi

# === Retention ===
if [[ "$RETENTION_DAYS" -gt 0 ]]; then
  find "$BACKUP_DIR" -type f -name "${_sanitized_basename}-*.sql.gz" -mtime +"$RETENTION_DAYS" -print -delete | \
    sed 's/^/[DELETE] /' | tee -a "$LOG_FILE" || true
fi

echo "[$(date +'%F %T')] Finished." | tee -a "$LOG_FILE"
