#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Docker DB backup/restore (MySQL or Postgres)
# - Reads ALL configuration from an env file.
# - Env file path is changeable via --env-file or ENV_FILE.
# - Default env file path: /root/env/mysql_backup/.env (overrideable)
# - Backup: dumps all DBs by default; optional single DB via MYSQL_DATABASE/POSTGRES_DATABASE.
# - Restore: requires --restore /path/to/dump.sql[.gz]
# - Uses docker exec to run mysqldump/mysql or pg_dump/psql inside the container.
# =========================================================

usage() {
  cat <<EOF
Usage: $0 [--env-file /path/to/.env] [--postgres|--mysql] [--restore /path/to/dump.sql[.gz]]

Modes:
  - default is backup (no --restore)
  - use --restore with a dump file path to restore

Engines (optional):
  --mysql      Use MySQL/MariaDB (default)
  --postgres   Use PostgreSQL

Env expectations (depending on engine):
  Common:   DOCKER_CONTAINER, BACKUP_DIR, BACKUP_BASENAME, RETENTION_DAYS, LOG_FILE
  MySQL:    MYSQL_USER, MYSQL_PASSWORD, [MYSQL_DATABASE]
  Postgres: POSTGRES_USER, POSTGRES_PASSWORD, [POSTGRES_DATABASE]

Examples:
  $0 --env-file /path/.env                          # MySQL backup (default)
  $0 --postgres --env-file /path/.env               # Postgres backup
  $0 --restore /backups/dump.sql.gz                 # MySQL restore
  $0 --postgres --restore /backups/pg_dump.sql.gz   # Postgres restore
EOF
}

ENV_FILE_DEFAULT="/root/env/mysql_backup/.env"
ENV_FILE="${ENV_FILE:-$ENV_FILE_DEFAULT}"

ENGINE="mysql"        # mysql | postgres
ACTION="backup"       # backup | restore
RESTORE_FILE=""

# --- Parse minimal flags (keep backwards-compatible with existing --env-file) ---
args=("$@")
i=0
while (( i < ${#args[@]} )); do
  case "${args[$i]}" in
    -h|--help)
      usage; exit 0;;
    --env-file)
      if (( i+1 >= ${#args[@]} )); then echo "--env-file requires a value" >&2; exit 1; fi
      ENV_FILE="${args[$((i+1))]}"; i=$((i+2)); continue;;
    --postgres)
      ENGINE="postgres"; i=$((i+1)); continue;;
    --mysql)
      ENGINE="mysql"; i=$((i+1)); continue;;
    --restore)
      if (( i+1 >= ${#args[@]} )); then echo "--restore requires a dump file path" >&2; exit 1; fi
      ACTION="restore"; RESTORE_FILE="${args[$((i+1))]}"; i=$((i+2)); continue;;
    *)
      # ignore unknown for now (keeps backwards compatibility);
      # no positional args expected
      i=$((i+1));;
  esac
done

# === Load required environment file ===
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Required env file not found: $ENV_FILE"
  echo "Default path is $ENV_FILE_DEFAULT (override with --env-file)"
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

# === Common config (with sane defaults) ===
DOCKER_CONTAINER="${DOCKER_CONTAINER:?Set DOCKER_CONTAINER in env file}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/$ENGINE}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
BACKUP_BASENAME="${BACKUP_BASENAME:-all-databases}"
LOG_FILE="${LOG_FILE:-$BACKUP_DIR/backup.log}"

timestamp="$(date +'%Y%m%d-%H%M%S')"
mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"

# --- Logging (logfmt) ---
# ts=... level=info engine=mysql action=backup container=name msg="..." [key=value ...]
log() {
  local level="$1"; shift || true
  local msg="${1:-}"; shift || true
  local ts
  ts="$(date -Iseconds)"
  # Escape quotes in message for logfmt quoted value
  local esc_msg="${msg//"/\\"}"
  local line="ts=$ts level=$level engine=$ENGINE action=$ACTION container=$DOCKER_CONTAINER msg=\"$esc_msg\""
  for kv in "$@"; do
    line+=" $kv"
  done
  echo "$line" | tee -a "$LOG_FILE"
}

# Sanitize basename to avoid weird filenames
_sanitized_basename="$(printf '%s' "$BACKUP_BASENAME" | tr -cd 'A-Za-z0-9._-')"
if [[ -z "$_sanitized_basename" ]]; then
  _sanitized_basename="all-databases"
fi

# === Engine-specific helpers ===
backup_mysql() {
  local MYSQL_USER="${MYSQL_USER:?Set MYSQL_USER in env file}"
  local MYSQL_PASSWORD="${MYSQL_PASSWORD:?Set MYSQL_PASSWORD in env file}"
  local MYSQL_DATABASE="${MYSQL_DATABASE:-}"   # if empty => all databases

  log info "Starting MySQL backup" \
    backup_dir="$BACKUP_DIR" basename="$_sanitized_basename"

  local outfile="$BACKUP_DIR/${_sanitized_basename}-${timestamp}.sql.gz"

  # Build dump args
  local dump_args=(
    -u"$MYSQL_USER"
    --single-transaction
    --quick
    --routines
    --triggers
    --events
    --hex-blob
    --set-gtid-purged=OFF
    --skip-lock-tables
  )
  if [[ -n "$MYSQL_DATABASE" && "$MYSQL_DATABASE" != "*" ]]; then
    dump_args+=(--databases "$MYSQL_DATABASE")
  else
    dump_args+=(--all-databases)
  fi

  if docker exec \
    --env MYSQL_PWD="$MYSQL_PASSWORD" \
    "$DOCKER_CONTAINER" \
    mysqldump "${dump_args[@]}" 2>>"$LOG_FILE" \
    | gzip -c > "$outfile"; then
    :
  else
    log error "Backup failed (mysqldump/docker exec error)" outfile="$outfile"
    exit 2
  fi

  if gzip -t "$outfile" 2>>"$LOG_FILE"; then
    log info "Backup OK" outfile="$outfile"
  else
    log error "Backup failed (gzip test)" outfile="$outfile"
    exit 3
  fi

  if [[ "${RETENTION_DAYS:-0}" -gt 0 ]]; then
    while IFS= read -r -d '' f; do
      rm -f -- "$f" && log info "Deleted expired backup" file="$f"
    done < <(find "$BACKUP_DIR" -type f -name "${_sanitized_basename}-*.sql.gz" -mtime +"$RETENTION_DAYS" -print0)
  fi

  log info "Finished MySQL backup"
}

restore_mysql() {
  local MYSQL_USER="${MYSQL_USER:?Set MYSQL_USER in env file}"
  local MYSQL_PASSWORD="${MYSQL_PASSWORD:?Set MYSQL_PASSWORD in env file}"
  local MYSQL_DATABASE="${MYSQL_DATABASE:-}"   # optional
  local infile="$RESTORE_FILE"

  log info "Starting MySQL restore" infile="$infile"

  if [[ ! -f "$infile" ]]; then
    log error "Restore file not found" infile="$infile"; exit 1
  fi

  # Choose mysql CLI args; if single DB specified, use --database to ensure target
  local mysql_args=( -u"$MYSQL_USER" )
  if [[ -n "$MYSQL_DATABASE" && "$MYSQL_DATABASE" != "*" ]]; then
    mysql_args+=( --database "$MYSQL_DATABASE" )
  fi

  if [[ "$infile" == *.gz ]]; then
    if gzip -t "$infile" 2>>"$LOG_FILE"; then :; else log error "Gzip file is corrupt" infile="$infile"; exit 3; fi
    if gzip -cd -- "$infile" | docker exec -i --env MYSQL_PWD="$MYSQL_PASSWORD" "$DOCKER_CONTAINER" mysql "${mysql_args[@]}" 2>>"$LOG_FILE"; then
      log info "Restore OK"
    else
      log error "Restore failed (mysql/docker exec error)"; exit 2
    fi
  else
    if docker exec -i --env MYSQL_PWD="$MYSQL_PASSWORD" "$DOCKER_CONTAINER" mysql "${mysql_args[@]}" 2>>"$LOG_FILE" < "$infile"; then
      log info "Restore OK"
    else
      log error "Restore failed (mysql/docker exec error)"; exit 2
    fi
  fi
}

backup_postgres() {
  local POSTGRES_USER="${POSTGRES_USER:?Set POSTGRES_USER in env file}"
  local POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD in env file}"
  local POSTGRES_DATABASE="${POSTGRES_DATABASE:-}"   # if empty => all databases

  log info "Starting Postgres backup" backup_dir="$BACKUP_DIR" basename="$_sanitized_basename"

  local outfile="$BACKUP_DIR/${_sanitized_basename}-${timestamp}.sql.gz"

  if [[ -n "$POSTGRES_DATABASE" && "$POSTGRES_DATABASE" != "*" ]]; then
    # Single database
    if docker exec \
      --env PGPASSWORD="$POSTGRES_PASSWORD" \
      "$DOCKER_CONTAINER" \
      pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" --clean --if-exists --no-owner --no-privileges 2>>"$LOG_FILE" \
      | gzip -c > "$outfile"; then
      :
    else
      log error "Backup failed (pg_dump/docker exec error)" outfile="$outfile"; exit 2
    fi
  else
    # All databases
    if docker exec \
      --env PGPASSWORD="$POSTGRES_PASSWORD" \
      "$DOCKER_CONTAINER" \
      pg_dumpall -U "$POSTGRES_USER" --clean --if-exists 2>>"$LOG_FILE" \
      | gzip -c > "$outfile"; then
      :
    else
      log error "Backup failed (pg_dumpall/docker exec error)" outfile="$outfile"; exit 2
    fi
  fi

  if gzip -t "$outfile" 2>>"$LOG_FILE"; then
    log info "Backup OK" outfile="$outfile"
  else
    log error "Backup failed (gzip test)" outfile="$outfile"; exit 3
  fi

  if [[ "${RETENTION_DAYS:-0}" -gt 0 ]]; then
    while IFS= read -r -d '' f; do
      rm -f -- "$f" && log info "Deleted expired backup" file="$f"
    done < <(find "$BACKUP_DIR" -type f -name "${_sanitized_basename}-*.sql.gz" -mtime +"$RETENTION_DAYS" -print0)
  fi

  log info "Finished Postgres backup"
}

restore_postgres() {
  local POSTGRES_USER="${POSTGRES_USER:?Set POSTGRES_USER in env file}"
  local POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD in env file}"
  local POSTGRES_DATABASE="${POSTGRES_DATABASE:-}"   # optional; for single-DB dumps
  local infile="$RESTORE_FILE"

  log info "Starting Postgres restore" infile="$infile"

  if [[ ! -f "$infile" ]]; then
    log error "Restore file not found" infile="$infile"; exit 1
  fi

  # Choose target database: if single DB provided, restore to that DB; otherwise default to 'postgres'
  local target_db="postgres"
  if [[ -n "$POSTGRES_DATABASE" && "$POSTGRES_DATABASE" != "*" ]]; then
    target_db="$POSTGRES_DATABASE"
  fi

  if [[ "$infile" == *.gz ]]; then
    if gzip -t "$infile" 2>>"$LOG_FILE"; then :; else log error "Gzip file is corrupt" infile="$infile"; exit 3; fi
    if gzip -cd -- "$infile" | docker exec -i --env PGPASSWORD="$POSTGRES_PASSWORD" "$DOCKER_CONTAINER" psql -U "$POSTGRES_USER" -d "$target_db" 2>>"$LOG_FILE"; then
      log info "Restore OK"
    else
      log error "Restore failed (psql/docker exec error)"; exit 2
    fi
  else
    if docker exec -i --env PGPASSWORD="$POSTGRES_PASSWORD" "$DOCKER_CONTAINER" psql -U "$POSTGRES_USER" -d "$target_db" 2>>"$LOG_FILE" < "$infile"; then
      log info "Restore OK"
    else
      log error "Restore failed (psql/docker exec error)"; exit 2
    fi
  fi
}

# === Dispatch ===
case "$ENGINE:$ACTION" in
  mysql:backup)
    backup_mysql ;;
  mysql:restore)
    if [[ -z "$RESTORE_FILE" ]]; then echo "--restore requires a dump file" >&2; exit 1; fi
    restore_mysql ;;
  postgres:backup)
    backup_postgres ;;
  postgres:restore)
    if [[ -z "$RESTORE_FILE" ]]; then echo "--restore requires a dump file" >&2; exit 1; fi
    restore_postgres ;;
  *)
    echo "Unknown mode: engine=$ENGINE action=$ACTION" >&2; usage; exit 1 ;;
esac
