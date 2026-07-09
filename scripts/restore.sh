#!/bin/bash
# =============================================================================
# n8n Restore Script
# =============================================================================
# Usage: ./scripts/restore.sh <backup-file.tar.gz>
# =============================================================================

set -euo pipefail

BACKUP_FILE="${1:-}"
COMPOSE_FILE="/opt/n8n-whatsapp-crm/docker/docker-compose.yml"
VOLUME_NAME="n8n_data"

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <backup-file.tar.gz>"
  echo ""
  echo "Available backups:"
  ls -lh /opt/n8n-whatsapp-crm/backups/*.tar.gz 2>/dev/null || echo "  No backups found."
  exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "Error: File not found: $BACKUP_FILE"
  exit 1
fi

echo "=================================================="
echo "  n8n Restore"
echo "=================================================="
echo "  Backup file: $BACKUP_FILE"
echo "  Size:        $(du -sh "$BACKUP_FILE" | cut -f1)"
echo "=================================================="
echo ""
echo "WARNING: This will OVERWRITE all current n8n data."
echo "         Workflows, credentials, and DataTable data will be replaced."
echo ""
read -rp "Type 'yes' to confirm: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Restore cancelled."
  exit 0
fi

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopping n8n..."
docker compose -f "${COMPOSE_FILE}" down

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Clearing existing volume data..."
docker run --rm \
  -v "${VOLUME_NAME}:/data" \
  alpine sh -c "rm -rf /data/* /data/.[!.]*"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restoring from backup..."
BACKUP_DIR=$(dirname "$(realpath "$BACKUP_FILE")")
BACKUP_NAME=$(basename "$BACKUP_FILE")

docker run --rm \
  -v "${VOLUME_NAME}:/data" \
  -v "${BACKUP_DIR}:/backup" \
  alpine tar xzf "/backup/${BACKUP_NAME}" -C /data

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting n8n..."
docker compose -f "${COMPOSE_FILE}" up -d

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restore complete."
echo "  Check status: docker compose -f ${COMPOSE_FILE} ps"
echo "  View logs:    docker compose -f ${COMPOSE_FILE} logs -f n8n"
