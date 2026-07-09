# Backup & Restore — WhatsApp CRM Automation

---

## What to Back Up

| Item | Location | Criticality | Frequency |
|------|----------|-------------|-----------|
| n8n workflow JSON | n8n UI → Export | CRITICAL | After every change |
| n8n credentials | n8n Docker volume | CRITICAL | Daily |
| n8n database (SQLite) | Docker volume `/home/node/.n8n/database.sqlite` | CRITICAL | Daily |
| n8n DataTable data | Docker volume (embedded in SQLite) | HIGH | Daily |
| Docker volume (full) | Host volume `n8n_data` | CRITICAL | Daily |
| `.env` file | Server filesystem | CRITICAL | After every change |
| `workflow.json` | Git repository | HIGH | After every change |
| nginx config | `/etc/nginx/sites-available/n8n` | MEDIUM | After every change |

---

## Backup Procedures

### 1. Export Workflow JSON (Manual — after every workflow change)

```bash
# In n8n UI:
# Open workflow → ⋮ (three dots) → Download
# Save to: project/workflow/workflow.json
# Commit to Git immediately

# Or via n8n CLI inside container:
docker exec n8n-whatsapp-crm n8n export:workflow --all --output=/home/node/.n8n/exports/
docker cp n8n-whatsapp-crm:/home/node/.n8n/exports/ ./backups/workflows-$(date +%Y%m%d)/
```

### 2. Full Docker Volume Backup (Recommended — Daily)

This single backup captures everything: database, credentials, DataTable, workflows.

```bash
#!/bin/bash
# Save as: scripts/backup.sh
# Make executable: chmod +x scripts/backup.sh

BACKUP_DIR="/opt/n8n-whatsapp-crm/backups"
VOLUME_NAME="n8n_data"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/n8n-backup-${TIMESTAMP}.tar.gz"

# Create backup directory if not exists
mkdir -p "${BACKUP_DIR}"

echo "Starting backup at ${TIMESTAMP}..."

# Stop n8n for consistent backup (recommended)
docker compose -f /opt/n8n-whatsapp-crm/docker/docker-compose.yml stop n8n

# Create compressed archive of n8n volume
docker run --rm \
  --name n8n-backup-runner \
  -v ${VOLUME_NAME}:/source:ro \
  -v ${BACKUP_DIR}:/backup \
  alpine tar czf /backup/n8n-backup-${TIMESTAMP}.tar.gz -C /source .

# Restart n8n
docker compose -f /opt/n8n-whatsapp-crm/docker/docker-compose.yml start n8n

echo "Backup saved: ${BACKUP_FILE}"
echo "Size: $(du -sh ${BACKUP_FILE} | cut -f1)"

# Retain only last 14 backups
ls -t ${BACKUP_DIR}/n8n-backup-*.tar.gz | tail -n +15 | xargs -r rm

echo "Backup complete. Retained last 14 backups."
```

### 3. SQLite Database Only Backup (Lightweight)

```bash
# Copy SQLite file directly from container
docker cp n8n-whatsapp-crm:/home/node/.n8n/database.sqlite \
  ./backups/database-$(date +%Y%m%d-%H%M%S).sqlite

echo "SQLite backup complete"
```

### 4. Environment File Backup

```bash
# Encrypt .env before storing offsite
gpg --symmetric --cipher-algo AES256 .env
# Creates: .env.gpg — safe to store in offsite backup

# Restore:
gpg --decrypt .env.gpg > .env
```

### 5. Automated Daily Backup (Cron)

```bash
# Install the backup script
sudo cp /opt/n8n-whatsapp-crm/scripts/backup.sh /usr/local/bin/n8n-backup
sudo chmod +x /usr/local/bin/n8n-backup

# Add to cron (runs daily at 02:00 AM)
echo "0 2 * * * ubuntu /usr/local/bin/n8n-backup >> /var/log/n8n-backup.log 2>&1" | \
  sudo tee -a /etc/cron.d/n8n-backup

# Verify cron entry
sudo crontab -l
```

### 6. Offsite Backup (Optional but Recommended)

```bash
# Sync backups to AWS S3 (install aws-cli first)
aws s3 sync /opt/n8n-whatsapp-crm/backups/ s3://your-backup-bucket/n8n/

# Or use rclone for any cloud storage provider
rclone copy /opt/n8n-whatsapp-crm/backups/ remote:n8n-backups/
```

---

## Restore Procedures

### Restore from Full Volume Backup

```bash
#!/bin/bash
# Usage: ./scripts/restore.sh backups/n8n-backup-YYYYMMDD-HHMMSS.tar.gz

BACKUP_FILE=$1
VOLUME_NAME="n8n_data"

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <backup-file.tar.gz>"
  exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "Error: Backup file not found: $BACKUP_FILE"
  exit 1
fi

echo "Restoring from: ${BACKUP_FILE}"
echo "WARNING: This will overwrite all current n8n data."
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Restore cancelled."
  exit 0
fi

# Stop n8n
docker compose -f /opt/n8n-whatsapp-crm/docker/docker-compose.yml down

# Clear existing volume data
docker run --rm \
  -v ${VOLUME_NAME}:/data \
  alpine sh -c "rm -rf /data/*"

# Restore from backup
docker run --rm \
  -v ${VOLUME_NAME}:/data \
  -v $(dirname $(realpath $BACKUP_FILE)):/backup \
  alpine tar xzf /backup/$(basename $BACKUP_FILE) -C /data

# Restart n8n
docker compose -f /opt/n8n-whatsapp-crm/docker/docker-compose.yml up -d

echo "Restore complete. n8n restarting..."
echo "Check status: docker compose ps"
```

### Restore Workflow Only (without full restore)

```bash
# In n8n UI:
# Open workflow → ⋮ → Import from File → select workflow.json
# Or delete existing workflow and re-import
```

### Restore SQLite Database Only

```bash
# Stop n8n
docker compose down

# Copy SQLite backup into volume
docker run --rm \
  -v n8n_data:/data \
  -v $(pwd)/backups:/backup \
  alpine cp /backup/database-YYYYMMDD-HHMMSS.sqlite /data/database.sqlite

# Restart n8n
docker compose up -d
```

---

## Backup Verification

After every backup, verify it can be restored:

```bash
# List backup contents
docker run --rm \
  -v $(pwd)/backups:/backup \
  alpine tar -tvf /backup/n8n-backup-YYYYMMDD-HHMMSS.tar.gz | head -20

# Check backup file integrity
tar -tzf backups/n8n-backup-YYYYMMDD-HHMMSS.tar.gz > /dev/null && echo "OK" || echo "CORRUPT"

# Check backup size (should be > 10KB for a working n8n install)
du -sh backups/n8n-backup-YYYYMMDD-HHMMSS.tar.gz
```

---

## Backup Retention Policy

| Type | Retention |
|------|-----------|
| Daily automated backups | 14 days |
| Weekly manual backup | 4 weeks |
| Monthly backup before major changes | 3 months |
| Pre-deployment backup | Keep permanently |

---

## Important Notes

> **WARNING:** The `.env` file contains secrets (API keys, tokens, encryption key). Never backup `.env` to unencrypted storage or commit to Git.

> **WARNING:** The n8n encryption key (`N8N_ENCRYPTION_KEY`) is required to decrypt stored credentials. If this key is lost, all n8n credentials must be re-entered manually. Always store the encryption key separately from the volume backup.

> **INFO:** n8n DataTable data is stored inside the n8n SQLite database. The full volume backup covers it.

> **INFO:** WhatsApp conversation state is stored in the DataTable. If state data is lost, active conversations will restart from the beginning — customers will need to re-enter their details.
