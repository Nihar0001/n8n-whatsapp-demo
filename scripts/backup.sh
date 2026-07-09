#!/bin/bash
# =============================================================================
# n8n Backup Script
# =============================================================================
# Usage:   ./scripts/backup.sh
# Cron:    0 2 * * * /usr/local/bin/n8n-backup >> /var/log/n8n-backup.log 2>&1
# =============================================================================

set -euo pipefail

BACKUP_DIR="/opt/n8n-whatsapp-crm/backups"
COMPOSE_FILE="/opt/n8n-whatsapp-crm/docker/docker-compose.yml"
VOLUME_NAME="n8n_data"
KEEP_LAST=14
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/n8n-backup-${TIMESTAMP}.tar.gz"

mkdir -p "${BACKUP_DIR}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting n8n backup..."

# Stop n8n for consistent backup
docker compose -f "${COMPOSE_FILE}" stop n8n
echo "[$(date '+%Y-%m-%d %H:%M:%S')] n8n stopped."

# Create backup
docker run --rm \
  --name n8n-backup-runner \
  -v "${VOLUME_NAME}:/source:ro" \
  -v "${BACKUP_DIR}:/backup" \
  alpine tar czf "/backup/n8n-backup-${TIMESTAMP}.tar.gz" -C /source .

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup created: ${BACKUP_FILE}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Size: $(du -sh "${BACKUP_FILE}" | cut -f1)"

# Restart n8n
docker compose -f "${COMPOSE_FILE}" start n8n
echo "[$(date '+%Y-%m-%d %H:%M:%S')] n8n restarted."

# Prune old backups
ls -t "${BACKUP_DIR}"/n8n-backup-*.tar.gz 2>/dev/null | tail -n +$((KEEP_LAST + 1)) | xargs -r rm
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Retained last ${KEEP_LAST} backups."

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup complete."
