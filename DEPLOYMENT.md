# Deployment Guide — WhatsApp CRM Automation

**Target OS:** Ubuntu 22.04 LTS (or 24.04 LTS)
**Required by:** DevOps Engineer

---

## Prerequisites Checklist

Before starting, confirm you have:

- [ ] Ubuntu 22.04 or 24.04 LTS server with root or sudo access
- [ ] Domain name pointing to server IP (A record set)
- [ ] Ports 22, 80, 443 open in cloud firewall/security group
- [ ] Laravel CRM API URL and Bearer token
- [ ] Meta Business Manager access (WhatsApp webhook configuration)
- [ ] Google AI Studio API key (if using Gemini)

---

## Step 1 — Server Initial Setup

```bash
# Connect to server
ssh ubuntu@YOUR_SERVER_IP

# Update system packages
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y curl wget git ufw fail2ban unzip
```

---

## Step 2 — Configure Firewall

```bash
# Set UFW defaults
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow required ports only
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP (for SSL certificate challenge)
sudo ufw allow 443/tcp     # HTTPS (webhook + n8n UI)

# Enable firewall
sudo ufw enable

# Verify
sudo ufw status verbose
```

---

## Step 3 — Install Docker

```bash
# Remove old Docker versions if any
sudo apt remove -y docker docker-engine docker.io containerd runc

# Install Docker prerequisites
sudo apt install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

# Add Docker GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine and Docker Compose
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group (avoids needing sudo for docker commands)
sudo usermod -aG docker $USER
newgrp docker

# Verify installation
docker --version
docker compose version
```

---

## Step 4 — Install & Configure Nginx

```bash
# Install nginx
sudo apt install -y nginx

# Remove default site
sudo rm -f /etc/nginx/sites-enabled/default

# Create n8n site configuration
sudo nano /etc/nginx/sites-available/n8n
```

Paste the following (replace `n8n.yourdomain.com` with your actual domain):

```nginx
# Redirect HTTP → HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name n8n.yourdomain.com;
    return 301 https://$host$request_uri;
}

# HTTPS reverse proxy to n8n
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name n8n.yourdomain.com;

    # SSL certificates (filled in by Certbot — see Step 5)
    # ssl_certificate /etc/letsencrypt/live/n8n.yourdomain.com/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/n8n.yourdomain.com/privkey.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";

    # Proxy to n8n
    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        client_max_body_size 50M;
    }
}
```

```bash
# Enable the site
sudo ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n

# Test nginx config
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
```

---

## Step 5 — Install SSL Certificate

```bash
# Install Certbot
sudo apt install -y certbot python3-certbot-nginx

# Obtain SSL certificate (replace with your domain)
sudo certbot --nginx -d n8n.yourdomain.com \
  --non-interactive \
  --agree-tos \
  --email your-email@domain.com

# Verify auto-renewal
sudo certbot renew --dry-run

# Verify SSL
curl -I https://n8n.yourdomain.com
```

---

## Step 6 — Deploy Application

```bash
# Create deployment directory
sudo mkdir -p /opt/n8n-whatsapp-crm
sudo chown $USER:$USER /opt/n8n-whatsapp-crm
cd /opt/n8n-whatsapp-crm

# Clone repository
git clone https://github.com/your-org/n8n-whatsapp-crm.git .

# Create backups directory
mkdir -p backups
```

---

## Step 7 — Configure Environment

```bash
# Navigate to docker directory
cd /opt/n8n-whatsapp-crm/docker

# Copy environment template to docker directory
cp ../.env.example .env

# Edit environment file — fill in ALL values
nano .env
```

**Required values to set:**

```env
N8N_ENCRYPTION_KEY=<run: openssl rand -hex 32>
WEBHOOK_URL=https://n8n.yourdomain.com
N8N_BASIC_AUTH_PASSWORD=<strong password>
N8N_ENVS_MODE=local
N8N_BLOCK_ENV_ACCESS_IN_NODE=false
WHATSAPP_PHONE_NUMBER_ID=<from Meta Business>
WHATSAPP_ACCESS_TOKEN=<from Meta Business — permanent system user token>
WHATSAPP_VERIFY_TOKEN=<your chosen secret: openssl rand -hex 16>
CRM_API_URL=https://crm.yourdomain.com/api/automation/leads
CRM_API_TOKEN=<from Laravel>
GEMINI_API_KEY=<from Google AI Studio>
```

---

## Step 8 — Start n8n

```bash
# Start containers (run from the docker/ directory)
docker compose up -d

# Verify container is running
docker compose ps

# Check logs
docker compose logs -f n8n

# Verify healthcheck
docker inspect --format='{{.State.Health.Status}}' n8n-whatsapp-crm
# Expected output: healthy
```

n8n should now be accessible at: `https://n8n.yourdomain.com`

---

## Step 9 — Import Workflow

1. Open `https://n8n.yourdomain.com` in your browser
2. Log in (username/password from `.env`)
3. Click **"+"** → **Import from File**
4. Upload `workflow/workflow.json`
5. Click **Save** (do NOT activate yet)

---

## Step 10 — Configure Credentials in n8n

### WhatsApp Business Cloud API

1. n8n → **Credentials** (left sidebar) → **Add Credential**
2. Search: **WhatsApp Business Cloud API**
3. Fill in:
   - **Access Token:** value of `WHATSAPP_ACCESS_TOKEN`
   - **Phone Number ID:** value of `WHATSAPP_PHONE_NUMBER_ID`
4. Click **Save**
5. In the workflow, assign this credential to all **WhatsApp Send** nodes

### Google Gemini (PaLM) API

1. n8n → **Credentials** → **Add Credential**
2. Search: **Google PaLM API**
3. Fill in:
   - **API Key:** value of `GEMINI_API_KEY`
4. Click **Save**
5. In the workflow, assign to the **AI: Extract Lead Data** node

---

## Step 11 — Configure WhatsApp Webhook in Meta

1. Go to [Meta Business Manager](https://business.facebook.com)
2. **Apps** → Your App → **WhatsApp** → **Configuration**
3. Under **Webhooks**, click **Edit**
4. Set:
   - **Callback URL:** `https://n8n.yourdomain.com/webhook/whatsapp-lead-capture`
   - **Verify Token:** same value as `WHATSAPP_VERIFY_TOKEN` in `.env`
5. Click **Verify and Save**
6. Under **Webhook Fields**, enable: **messages**

---

## Step 12 — Activate Workflow

1. Open the workflow in n8n
2. Toggle the **Active** switch (top-right)
3. Confirm green "Active" status

---

## Step 13 — Production Verification

```bash
# Test webhook GET (verification)
curl -X GET "https://n8n.yourdomain.com/webhook/whatsapp-lead-capture?hub.mode=subscribe&hub.verify_token=YOUR_VERIFY_TOKEN&hub.challenge=test123"
# Expected: test123

# Test n8n health
curl -s https://n8n.yourdomain.com/healthz
# Expected: {"status":"ok"}

# Send a WhatsApp message to your number
# Follow the conversation flow
# Verify lead in Laravel CRM
```

---

## Rollback Procedure

```bash
cd /opt/n8n-whatsapp-crm/docker

# Stop current containers
docker compose down

# Restore from backup (see BACKUP.md)
./scripts/restore.sh backups/n8n-backup-YYYYMMDD-HHMMSS.tar.gz

# Restart
docker compose up -d
```

---

## Maintenance Commands

```bash
# View live logs
docker compose logs -f n8n

# Restart n8n (after .env changes)
docker compose restart n8n

# Update n8n to latest version
docker compose pull n8n
docker compose up -d n8n

# Check disk usage
docker system df

# Clean up old Docker images
docker image prune -f
```

---

## Post-Deployment Checklist

See [docs/CHECKLIST.md](../docs/CHECKLIST.md) for the complete production go-live checklist.
