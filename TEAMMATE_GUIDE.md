# 👋 Hey Teammate — Server Setup Guide

**For:** The DevOps teammate who will set up the server for n8n.

---

## What We Need From You

We are running a WhatsApp automation using **n8n** (self-hosted).
It needs a Linux server with Docker. Here is exactly what we need.

---

## Option A — Give Us SSH Access (Easiest)

If you already have a server (any VPS, cloud VM, etc.), just give us:

```
Server IP:     e.g.  123.45.67.89
SSH Username:  e.g.  ubuntu  (or root)
SSH Password:  e.g.  xxxxxxxx
          OR
SSH Key file:  send us the .pem or private key file
Port:          22 (default)
```

We will handle everything else — Docker, nginx, n8n, configuration.

**That's it.** We just need those 3–4 things.

---

## Option B — Free Server Options (No Money Needed)

If you don't have a server yet, here are **completely free** options:

### 🥇 Best Option: Oracle Cloud Free Tier (Always Free Forever)

This is genuinely free — not a trial. Oracle gives you:
- **4 CPU + 24 GB RAM** ARM server (Ampere A1)
- **OR** 2x micro VMs (AMD, 1 CPU, 1 GB RAM each)
- **200 GB block storage**
- Free forever (not a trial)

**Steps:**
1. Go to https://www.oracle.com/cloud/free/
2. Create an account (credit card required to verify identity, NOT charged)
3. Create an instance: **Ubuntu 22.04, Ampere A1 shape (4 OCPU, 24 GB)**
4. Download the SSH key during setup
5. Open ports 22, 80, 443 in Oracle Security List
6. Send us: IP address + SSH key file

---

### Option C: Other Free VPS Options

| Provider | Free Tier | Limits |
|----------|-----------|--------|
| **Google Cloud** | $300 credit (90 days) | Enough for 3 months |
| **AWS** | EC2 t2.micro (12 months) | 1 GB RAM only |
| **Azure** | $200 credit (30 days) | Limited time |
| **Fly.io** | Free shared VMs | 256 MB RAM — tight for n8n |
| **Railway** | $5/month credit free | Good for testing |

For production: **Oracle is the only truly free forever option.**

---

## Option D — We'll Set It Up Ourselves on Oracle

If you want, we can create the Oracle account ourselves. We just need:
- Access to a credit card for identity verification (not charged)
- That's literally it

---

## Minimum Server Requirements

| Requirement | Minimum | Ideal |
|-------------|---------|-------|
| OS | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |
| CPU | 1 vCPU | 2+ vCPU |
| RAM | **2 GB minimum** | 4 GB |
| Disk | 20 GB SSD | 40 GB SSD |
| Ports open | 22, 80, 443 | Same |
| Domain | One subdomain | e.g. n8n.yourdomain.com |

---

## What We Will Do Once We Have the Server

You don't need to install anything. We will handle:
1. Docker installation
2. nginx + SSL certificate (Let's Encrypt — free)
3. n8n container setup
4. Workflow import and configuration

---

## What You Need to Configure (Cloud Firewall)

Most cloud providers block ports by default. You need to allow:

```
Port 22  → SSH (only from your team's IPs ideally)
Port 80  → HTTP (for SSL certificate setup)
Port 443 → HTTPS (for the webhook URL)
```

In **Oracle Cloud:** Security List → Add Ingress Rules for those ports
In **AWS:** Security Group → Edit Inbound Rules
In **Google Cloud:** VPC Firewall → Add rules

---

## WhatsApp Credentials We Need From You / Meta

Besides the server, we also need WhatsApp credentials.

**If you manage the Meta Business account, please send:**

| Credential | Where to Get It | Example Format |
|------------|----------------|----------------|
| Phone Number ID | Meta Business → WhatsApp → API Setup | `1272089145976311` |
| Permanent Access Token | Meta Business → System Users → Generate Token | `EAABxxxxxx...` (very long string) |
| App Secret | Meta Business → Apps → Your App → Settings → Basic → App Secret | 32-character hex string |
| WABA ID | Meta Business → WhatsApp → Overview | `123456789012345` |

**IMPORTANT:** Use a **System User Token**, NOT a personal Facebook token.
- Go to: Business Settings → System Users → Add New → Give `whatsapp_business_messaging` permission → Generate Token
- System User Tokens do NOT expire. Page tokens expire every 60 days.

---

## CRM Credentials We Need From the Laravel Developer

| Credential | What It Is | How to Get |
|------------|------------|-----------|
| `CRM_API_URL` | Full URL to the lead creation endpoint | Change from ngrok to production URL |
| `CRM_API_TOKEN` | Bearer token for API authentication | `php artisan tinker` → `Str::random(64)` |

The Laravel endpoint should accept:
```json
POST /api/automation/leads
Authorization: Bearer {token}
{
  "phone": "919422512747",
  "name": "Customer Name",
  "company": "Company Name",
  "email": "email@domain.com",
  "ride": "Airport Transfer",
  "source": "whatsapp"
}
```

---

## Summary of What We Need From Everyone

| Who | What | Format |
|-----|------|--------|
| **DevOps / You** | Server SSH access | IP + username + password/key |
| **DevOps / You** | Domain pointed to server | DNS A record set |
| **Meta/WhatsApp admin** | Phone Number ID | `1272089145976311` (number) |
| **Meta/WhatsApp admin** | Permanent System User Token | `EAABxx...` |
| **Meta/WhatsApp admin** | App Secret | Hex string |
| **Laravel Developer** | Production CRM API URL | `https://crm.domain.com/api/automation/leads` |
| **Laravel Developer** | CRM API Bearer Token | Random 64-char string |

---

## Once We Have Everything

Total setup time after receiving credentials: **~2 hours**

The automation will:
1. Receive WhatsApp messages
2. Guide customers through Name → Company → Email → Ride questions
3. Submit lead data to your CRM
4. Send confirmation to the customer

Everything is already built, tested, and documented. We just need the server and credentials.

---

*Questions? Contact the automation developer.*
