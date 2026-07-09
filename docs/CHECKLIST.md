# Production Checklist — WhatsApp CRM Automation

**Use this checklist before every production go-live and after every major change.**

Mark each item `[x]` when confirmed. Do not activate the workflow until all CRITICAL items are checked.

---

## Section 1 — Infrastructure (DevOps)

### Server
- [ ] Ubuntu 22.04 LTS or 24.04 LTS installed and updated
- [ ] SSH key-based access configured (password auth disabled)
- [ ] Non-root deploy user created with sudo access
- [ ] Fail2ban installed and configured
- [ ] UFW firewall active with only ports 22, 80, 443 open

### Domain & SSL
- [ ] Domain A record points to server IP (`dig n8n.yourdomain.com`)
- [ ] SSL certificate issued by Let's Encrypt (`certbot certificates`)
- [ ] SSL auto-renewal working (`certbot renew --dry-run` succeeds)
- [ ] HTTPS redirects working (`curl -I http://n8n.yourdomain.com` returns 301)

### Docker
- [ ] Docker CE 24.x+ installed (`docker --version`)
- [ ] Docker Compose v2+ installed (`docker compose version`)
- [ ] Current user in docker group (no sudo needed for docker commands)

### Nginx
- [ ] Nginx installed and running (`systemctl status nginx`)
- [ ] n8n proxy config in `/etc/nginx/sites-available/n8n`
- [ ] Config test passes (`nginx -t`)
- [ ] WebSocket proxy headers configured (required for n8n UI)

---

## Section 2 — Environment Configuration

- [ ] `.env` file created from `.env.example`
- [ ] `N8N_ENCRYPTION_KEY` set to 32-character random hex (never default/blank)
- [ ] `N8N_BASIC_AUTH_PASSWORD` set to a strong password (minimum 16 characters)
- [ ] `WEBHOOK_URL` set to production HTTPS URL (no trailing slash)
- [ ] `WHATSAPP_PHONE_NUMBER_ID` set to correct Meta phone number ID
- [ ] `WHATSAPP_ACCESS_TOKEN` set to permanent system user token (not page token)
- [ ] `WHATSAPP_VERIFY_TOKEN` set to a random secret value
- [ ] `CRM_API_URL` set to production Laravel endpoint (NOT ngrok)
- [ ] `CRM_API_TOKEN` set to valid Laravel bearer token
- [ ] `GENERIC_TIMEZONE` set to correct timezone (`Asia/Kolkata`)
- [ ] `.env` file is NOT committed to Git (verify `.gitignore` contains `.env`)

---

## Section 3 — Docker & n8n

- [ ] Docker containers started (`docker compose up -d`)
- [ ] Container health is `healthy` (`docker inspect n8n-whatsapp-crm | grep Health`)
- [ ] n8n UI accessible at `https://n8n.yourdomain.com`
- [ ] n8n login works with configured credentials
- [ ] n8n `/healthz` returns `{"status":"ok"}` (`curl https://n8n.yourdomain.com/healthz`)
- [ ] n8n data volume mounted and persistent (`docker volume ls | grep n8n_data`)

---

## Section 4 — Workflow Import & Configuration

- [ ] Workflow imported from `workflow/workflow.json`
- [ ] All node names are professional/descriptive (no generic "Edit Fields", "HTTP Request")
- [ ] No hardcoded phone numbers in any WhatsApp send node
- [ ] No ngrok URLs in any HTTP Request node
- [ ] CRM HTTP Request has `Authorization: Bearer {{ $env.CRM_API_TOKEN }}` header
- [ ] `Lookup: Conversation by Phone` node uses dynamic filter (`phone == $json.phone`)
- [ ] `State: Mark Synced` node filters by row ID (not by `success isTrue`)
- [ ] All 5 Switch branches (initial, waiting_name, waiting_company, waiting_email, waiting_ride) are wired
- [ ] `waiting_ride` branch has CRM API call + success/error branches

---

## Section 5 — Credentials

- [ ] WhatsApp Business Cloud API credential created in n8n
- [ ] WhatsApp credential assigned to all WhatsApp send nodes in workflow
- [ ] Google Gemini (PaLM) API credential created in n8n (if AI path used)
- [ ] Google credential assigned to AI extraction node (if used)
- [ ] CRM API token passed via `$env.CRM_API_TOKEN` (no credential needed — env var)
- [ ] All credentials tested (send test message, verify CRM response)

---

## Section 6 — Webhook Verification

- [ ] `WA: Verify Token Webhook` node (GET) is correctly wired to `WA: Respond to Verification`
- [ ] Webhook URL verified manually:
  ```bash
  curl "https://n8n.yourdomain.com/webhook/whatsapp-lead-capture?hub.mode=subscribe&hub.verify_token=YOUR_TOKEN&hub.challenge=test123"
  # Expected: test123
  ```
- [ ] Meta Business Manager → WhatsApp → Webhooks → Status: **Connected**
- [ ] `messages` field is subscribed in Meta webhook settings
- [ ] Workflow is **Active** (green toggle in n8n)

---

## Section 7 — End-to-End Conversation Test

Run the full conversation from a real WhatsApp number (not the business number):

- [ ] Send first message → Bot replies: "Hello 👋 What is your name?"
- [ ] Send name → Bot replies: "What is your company name?"
- [ ] Send company → Bot replies: "What is your email address?"
- [ ] Send email → Bot replies: "Which ride are you interested in?"
- [ ] Send ride → Bot replies: "Thanks! Your details have been saved."
- [ ] Bot replies go to the correct number (the sender, not hardcoded)

---

## Section 8 — CRM Verification

- [ ] Lead created in Laravel CRM after conversation completion
- [ ] Lead `source` field is `whatsapp`
- [ ] Client record upserted (not duplicated) when same phone used twice
- [ ] Follow-up record created
- [ ] Audit trail entry created
- [ ] DataTable row updated: `status=synced`, `state=idle`, `completed=true`

---

## Section 9 — Error Path Test

- [ ] Temporarily break CRM URL → customer receives "Sorry, try again" message
- [ ] DataTable row shows `status=sync_failed` with error message in `error` field
- [ ] Fix CRM URL → customer sends any message → retry works
- [ ] Conversation resumes correctly after error

---

## Section 10 — State Machine Test

- [ ] Returning user (same phone) continues from correct state (not reset to initial)
- [ ] Sending a media message (image) does not crash the workflow
- [ ] Sending a WhatsApp status event does not create a row or crash
- [ ] Conversation resets correctly after 24h TTL (or manual reset via DataTable)

---

## Section 11 — Backup & Monitoring

- [ ] Backup script created at `/usr/local/bin/n8n-backup`
- [ ] Cron job configured for daily backup at 02:00 AM
- [ ] Test backup created and verified:
  ```bash
  n8n-backup
  ls -la /opt/n8n-whatsapp-crm/backups/
  tar -tzf backups/n8n-backup-*.tar.gz | head -5
  ```
- [ ] Backup stored in `/opt/n8n-whatsapp-crm/backups/`
- [ ] Offsite backup configured (S3 or equivalent) — _optional_
- [ ] Uptime monitoring configured (UptimeRobot or equivalent)
- [ ] Alert email/Slack set up for workflow execution failures — _optional_

---

## Section 12 — Security

- [ ] n8n not accessible on port 5678 directly from internet (only via nginx)
- [ ] n8n UI protected with `N8N_BASIC_AUTH_ACTIVE=true`
- [ ] CRM API uses HTTPS endpoint (not HTTP)
- [ ] WhatsApp access token is a permanent system user token
- [ ] `.env` file has permissions `600`: `chmod 600 .env`
- [ ] `N8N_ENCRYPTION_KEY` is backed up securely (separate from volume backup)
- [ ] Webhook signature validation implemented (or planned) — see SECURITY_REVIEW.md

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Automation Developer | | | |
| Laravel Developer | | | |
| DevOps Engineer | | | |

**Go-live approved:** [ ] YES  [ ] NO

**Notes:**

---

*Checklist version: 1.0 | Generated: 2026-07-08*
