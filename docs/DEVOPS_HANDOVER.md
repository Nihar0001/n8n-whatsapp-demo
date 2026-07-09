# DevOps Handover — WhatsApp CRM Automation

**Audience:** DevOps Engineer responsible for deploying and operating this system.
**Estimated setup time:** 2–4 hours (after server provisioning).

---

## What This System Is

An n8n automation workflow that:
1. Receives WhatsApp messages via webhook
2. Maintains conversation state in a database
3. Collects 4 fields from the customer (Name, Company, Email, Ride)
4. Submits data to a Laravel CRM API

Everything runs in a single Docker container. No microservices. No Kubernetes. No complexity.

---

## What You Need to Provide

| Item | Details |
|------|---------|
| **Server** | Ubuntu 22.04 LTS, minimum 2 vCPU, 2 GB RAM, 20 GB SSD |
| **Domain** | A subdomain pointing to server IP (e.g., `n8n.yourdomain.com`) |
| **Ports open** | 22 (SSH), 80 (HTTP), 443 (HTTPS) in cloud security group |
| **Outbound access** | Server must reach: Meta API, Google API, Laravel CRM API |

---

## What You Do NOT Need to Configure

- Database server (SQLite runs inside Docker volume)
- Redis, RabbitMQ, or any queue service
- Separate n8n worker processes
- Custom Docker images (uses official `n8nio/n8n:latest`)

---

## Required Ports

| Port | Direction | Purpose | Who Accesses |
|------|-----------|---------|-------------|
| 22 | Inbound | SSH admin access | DevOps team only (restrict by IP) |
| 80 | Inbound | HTTP → HTTPS redirect | Anyone (nginx redirects to 443) |
| 443 | Inbound | HTTPS — n8n UI + webhooks | Meta Cloud API + your team |
| 5678 | Internal only | n8n process | nginx → n8n (do NOT open in firewall) |

---

## Required Domain

- **One subdomain** is sufficient: `n8n.yourdomain.com`
- Set an A record pointing to the server's public IP
- Both GET (webhook verification) and POST (messages) use the same URL path:
  `https://n8n.yourdomain.com/webhook/whatsapp-lead-capture`

---

## Deployment Steps (Summary)

Full details in [DEPLOYMENT.md](../DEPLOYMENT.md). Summary:

```bash
# 1. Provision server (Ubuntu 22.04)
# 2. Install Docker + nginx + Certbot
# 3. Configure firewall (UFW)
# 4. Clone repository
git clone https://github.com/your-org/n8n-whatsapp-crm.git /opt/n8n-whatsapp-crm

# 5. Configure environment
cd /opt/n8n-whatsapp-crm/docker
cp ../.env.example .env
nano .env   # Fill in all values

# 6. Configure nginx reverse proxy (copy config from DEPLOYMENT.md)
# 7. Get SSL certificate (certbot)
# 8. Start n8n
docker compose up -d

# 9. Hand over to automation developer to:
#    - Import workflow
#    - Configure credentials
#    - Register Meta webhook
#    - Activate workflow
```

---

## Environment Variables (Your Responsibility)

You must provide the following values to fill in `.env`:

| Variable | Your Task |
|----------|-----------|
| `N8N_ENCRYPTION_KEY` | Generate: `openssl rand -hex 32` |
| `N8N_BASIC_AUTH_PASSWORD` | Choose a strong password for n8n UI login |
| `WEBHOOK_URL` | Set to `https://n8n.yourdomain.com` (your domain) |
| `GENERIC_TIMEZONE` | Set to server/business timezone (e.g., `Asia/Kolkata`) |
| `N8N_ENVS_MODE` | Set to `local` (allows workflows to access local variables) |
| `N8N_BLOCK_ENV_ACCESS_IN_NODE` | Set to `false` (enables node expressions to access env) |

These are provided by the automation/business team:

| Variable | Provided By |
|----------|-------------|
| `WHATSAPP_PHONE_NUMBER_ID` | Meta Business Manager admin |
| `WHATSAPP_ACCESS_TOKEN` | Meta Business Manager admin |
| `WHATSAPP_VERIFY_TOKEN` | Automation developer |
| `CRM_API_URL` | Laravel developer |
| `CRM_API_TOKEN` | Laravel developer |
| `GEMINI_API_KEY` | Google AI Studio account holder |

---

## Expected URLs After Deployment

| Purpose | URL |
|---------|-----|
| n8n UI | `https://n8n.yourdomain.com` |
| Webhook (messages) | `https://n8n.yourdomain.com/webhook/whatsapp-lead-capture` |
| Webhook (verification) | `https://n8n.yourdomain.com/webhook/whatsapp-lead-capture` |
| Health check | `https://n8n.yourdomain.com/healthz` |

---

## Reverse Proxy Configuration

Use nginx. The configuration is documented in [DEPLOYMENT.md](../DEPLOYMENT.md) — Step 4.

Key requirements:
- Proxy `https://n8n.yourdomain.com` → `http://127.0.0.1:5678`
- Pass WebSocket headers (required for n8n UI)
- Set `proxy_read_timeout 86400` (n8n uses long-polling)
- Add security headers (HSTS, X-Frame-Options, etc.)

---

## Firewall Rules

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp     # SSH — restrict to admin IP if possible
sudo ufw allow 80/tcp     # HTTP (redirect only)
sudo ufw allow 443/tcp    # HTTPS
sudo ufw enable
```

**Do NOT open port 5678.** n8n should only be accessible through nginx on 443.

---

## SSL

Use Certbot with Let's Encrypt:

```bash
sudo certbot --nginx -d n8n.yourdomain.com \
  --non-interactive --agree-tos --email ops@yourdomain.com
```

Auto-renewal is configured automatically by Certbot. Verify with:
```bash
sudo certbot renew --dry-run
```

---

## Backup Responsibility

| Task | Responsible | Frequency |
|------|-------------|-----------|
| Docker volume backup | DevOps | Daily (cron at 02:00) |
| Offsite backup | DevOps | Daily |
| `.env` secure backup | DevOps | After every change |
| Workflow JSON export | Automation Dev | After every change |

Setup the backup cron — see [docs/BACKUP.md](BACKUP.md).

**CRITICAL:** Back up the `N8N_ENCRYPTION_KEY` separately. Without it, all n8n credentials are unrecoverable.

---

## Monitoring Recommendations

| Tool | What to monitor | Alert on |
|------|----------------|----------|
| UptimeRobot (free) | `https://n8n.yourdomain.com/healthz` | Down > 1 minute |
| Docker health | Container health status | `unhealthy` state |
| Disk | Server disk usage | > 80% full |
| n8n Error Workflow | Execution failures | Any failure (configure inside n8n) |

---

## Update Procedure

```bash
cd /opt/n8n-whatsapp-crm/docker

# Pull latest n8n image
docker compose pull n8n

# Restart with new image (zero-downtime is NOT guaranteed for SQLite)
docker compose up -d n8n

# Verify
docker compose ps
docker compose logs n8n | tail -20
```

**Always back up before updating:**
```bash
n8n-backup && docker compose pull && docker compose up -d
```

---

## Contacts

| Role | Responsibility | Contact |
|------|----------------|---------|
| Automation Developer | Workflow, DataTable, state machine | — |
| Laravel Developer | CRM API, authentication | — |
| DevOps Engineer | Server, Docker, nginx, SSL, backups | — |
| Meta Business Admin | WhatsApp tokens, webhook config | — |

---

## Handover Checklist (Your Sign-Off)

- [ ] Server provisioned and hardened
- [ ] Docker installed and running
- [ ] nginx configured and tested
- [ ] SSL certificate issued and auto-renewal verified
- [ ] `.env` file created with all values
- [ ] n8n container running and healthy
- [ ] n8n accessible at `https://n8n.yourdomain.com`
- [ ] Backup cron job installed and tested
- [ ] Port 5678 NOT accessible from internet (verify with external port scan)
- [ ] SSH access confirmed for automation developer (for workflow import)

**Signed off by:** _________________________ **Date:** _____________
