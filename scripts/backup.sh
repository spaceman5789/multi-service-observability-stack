#!/bin/bash
set -euo pipefail

# --- Настройки ---
BACKUP_DIR="/tmp/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="appdb_backup_${TIMESTAMP}.sql.gz"
S3_BUCKET="${S3_BUCKET:-my-app-backups}"
RETENTION_DAYS=7

# --- Цвета для вывода ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[BACKUP]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" >&2; }

# --- Создаём директорию ---
mkdir -p "$BACKUP_DIR"

# --- Дамп базы ---
log "Starting backup of database..."
docker compose exec -T postgres pg_dump \
    -U "${DB_USER:-appuser}" \
    -d "${DB_NAME:-appdb}" \
    --no-owner \
    --no-privileges \
    | gzip > "${BACKUP_DIR}/${BACKUP_FILE}"

FILESIZE=$(du -h "${BACKUP_DIR}/${BACKUP_FILE}" | cut -f1)
log "Backup created: ${BACKUP_FILE} (${FILESIZE})"

# --- Загрузка в S3 ---
if command -v aws &> /dev/null; then
    log "Uploading to S3..."
    aws s3 cp "${BACKUP_DIR}/${BACKUP_FILE}" "s3://${S3_BUCKET}/backups/${BACKUP_FILE}"
    log "Uploaded to s3://${S3_BUCKET}/backups/${BACKUP_FILE}"

    # Удаляем старые бэкапы из S3
    log "Cleaning old backups (older than ${RETENTION_DAYS} days)..."
    CUTOFF_DATE=$(date -d "-${RETENTION_DAYS} days" +%Y-%m-%d 2>/dev/null \
                  || date -v-${RETENTION_DAYS}d +%Y-%m-%d)
    aws s3 ls "s3://${S3_BUCKET}/backups/" | while read -r line; do
        FILE_DATE=$(echo "$line" | awk '{print $1}')
        FILE_NAME=$(echo "$line" | awk '{print $4}')
        if [[ "$FILE_DATE" < "$CUTOFF_DATE" && -n "$FILE_NAME" ]]; then
            aws s3 rm "s3://${S3_BUCKET}/backups/${FILE_NAME}"
            log "Deleted old backup: ${FILE_NAME}"
        fi
    done
else
    log "AWS CLI not found — skipping S3 upload. Backup saved locally."
fi

# --- Очистка локальных файлов ---
find "$BACKUP_DIR" -name "appdb_backup_*.sql.gz" -mtime +${RETENTION_DAYS} -delete
log "Backup complete!"
