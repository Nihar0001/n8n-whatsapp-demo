# WhatsApp → CRM Automation

**n8n | WhatsApp Cloud API | Laravel CRM | Google Gemini**

A production-grade conversational lead capture automation. Customers interact via WhatsApp; the workflow guides them through a structured 4-step conversation and submits the collected lead data directly into the Laravel CRM.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Requirements](#3-requirements)
4. [Folder Structure](#4-folder-structure)
5. [Installation (Local)](#5-installation-local)
6. [Running Locally](#6-running-locally)
7. [Import Workflow](#7-import-workflow)
8. [Configure Credentials](#8-configure-credentials)
9. [Webhook Setup](#9-webhook-setup)
10. [Testing](#10-testing)
11. [Stopping & Updating](#11-stopping--updating)
12. [Backup & Restore](#12-backup--restore)

---

## 1. Project Overview

| Property | Value |
|----------|-------|
| **Workflow engine** | n8n (self-hosted, Docker) |
| **WhatsApp integration** | Meta WhatsApp Cloud API |
| **CRM backend** | Laravel (existing, separate server) |
| **AI enrichment** | Google Gemini 2.5 Flash (optional) |
| **State storage** | n8n DataTable (`whatsapp_conversations`) |
| **Conversation states** | `initial → waiting_name → waiting_company → waiting_email → waiting_ride → idle` |

### What it does

1. Customer sends any WhatsApp message.
2. Workflow checks conversation state in DataTable.
3. Bot asks: Name → Company → Email → Ride (one question per message).
4. On completion, submits all data to Laravel CRM API.
5. Laravel creates: Lead (always new) + Client (upsert) + Follow-up + Audit Trail.
6. Customer receives confirmation or error message.

---

## 2. Architecture
flowchart TD
    A[Customer WhatsApp] -->|HTTP POST| B[Meta Cloud API]
    B --> C[n8n Webhook<br>/webhook/whatsapp-lead-capture]
    
    C --> D{Text Guard}
    D -->|Drop Non-Text| STOP[End]
    D -->|Valid Text| E[Normalize Payload<br>name, phone, message]
    
    E --> F[Lookup Conversation<br>DataTable by phone]
    
    F --> G{Exists?}
    G -->|NO| H[Insert Row] --> I[Route by State]
    G -->|YES| I
    
    I -->|initial| J[Ask Name]
    I -->|waiting_name| K[Save Name<br>Ask Company]
    I -->|waiting_co| L[Save Company<br>Ask Email]
    I -->|waiting_email| M[Save Email<br>Ask Ride]
    
    M --> N[waiting_ride]
    N --> O[Save Ride]
    O --> P[Call CRM API] --> Q[(Laravel)]
    
    P --> R{CRM Result}
    R -->|Success| S[Mark Synced<br>Send Confirmation]
    R -->|Error| T[Mark Failed<br>Send Apology]
[ Customer WhatsApp ]
         │
         ▼ (HTTP POST)
[ Meta Cloud API ]
         │
         ▼
[ n8n Webhook: /webhook/whatsapp-lead-capture ]
         │
         ▼
┌─────────────────────────────────┐
│ Text Guard (If)                 │
│ ├─► Drop non-text (Stop)        │
│ └─► Pass text                   │
└────────────────┬────────────────┘
                 │
                 ▼
[ Normalize Payload: name, phone, message ]
                 │
                 ▼
[ Lookup Conversation (DataTable by phone) ]
                 │
                 ▼
┌─────────────────────────────────┐
│ Exists?                         │
│ ├─► NO  ──► Insert Row          │
│ └─► YES ──┐                     │
└───────────┼─────────────────────┘
            │
            ▼
[ Route by State (Switch) ]
  │
  ├─► initial        ──► Ask Name
  │
  ├─► waiting_name   ──► Save Name ──► Ask Company
  │
  ├─► waiting_co     ──► Save Company ──► Ask Email
  │
  └─► waiting_email  ──► Save Email ──► Ask Ride
                             │
                             ▼
                     [ waiting_ride ]
                             │
                             ▼
                     [ Save Ride ]
                             │
                             ▼
                     [ Call CRM API ] ──► [ Laravel ]
                             │
                     ┌───────┴───────┐
                     ▼               ▼
                 (Success)        (Error)
                     │               │
                     ▼               ▼
               Mark Synced      Mark Failed
               Send Confirm     Send Apology
```
Customer WhatsApp
      │
      ▼ (HTTP POST)
Meta Cloud API ──────────────────────────────────────────────►
                                                              │
                                                    n8n Webhook
                                                    /webhook/whatsapp-lead-capture
                                                              │
                                                    ┌─────────▼──────────┐
                                                    │  Text Guard (If)   │
                                                    │  drop non-text     │
                                                    └─────────┬──────────┘
                                                              │
                                                    Normalize Payload
                                                    {name, phone, message}
                                                              │
                                                    Lookup Conversation
                                                    (DataTable by phone)
                                                              │
                                                    ┌─────────▼──────────┐
                                                    │  Exists?           │
                                                    │  NO → Insert row   │
                                                    │  YES → continue    │
                                                    └─────────┬──────────┘
                                                              │
                                                    Route by State (Switch)
                                                              │
                                   ┌──────────────┬──────────┴──────────┬──────────────┐
                                   │              │                     │              │
                                initial      waiting_name          waiting_co    waiting_email
                                   │              │                     │              │
                               Ask Name      Save Name            Save Company   Save Email
                                              Ask Company          Ask Email      Ask Ride
                                                                                     │
                                                                              waiting_ride
                                                                                     │
                                                                              Save Ride
                                                                              Call CRM API ──► Laravel
                                                                                     │
                                                                         ┌──────────┴──────────┐
                                                                         │                     │
                                                                      Success               Error
                                                                      Mark synced        Mark failed
                                                                      Send confirm       Send apology
```

For the full architecture document see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## 3. Requirements

### Local development
| Tool | Minimum Version | Install |
|------|----------------|---------|
| Docker Desktop | 24.x | https://www.docker.com/products/docker-desktop |
| Docker Compose | v2.x | Bundled with Docker Desktop |
| Git | 2.x | https://git-scm.com |

### Production server (Ubuntu)
See [DEPLOYMENT.md](DEPLOYMENT.md) for complete server setup.

### External services
| Service | Purpose | Where to configure |
|---------|---------|-------------------|
| Meta Business Manager | WhatsApp Cloud API | https://business.facebook.com |
| Google AI Studio | Gemini API key | https://aistudio.google.com |
| Laravel CRM | Lead creation API | Your CRM server |
| Domain + SSL | Public webhook URL | Your DNS provider |

---

## 4. Folder Structure

```
n8n-whatsapp-crm/
│
├── workflow/
│   └── workflow.json              # n8n workflow (import this into n8n)
│
├── docker/
│   └── docker-compose.yml         # Docker Compose configuration
│
├── docs/
│   ├── ARCHITECTURE.md            # System architecture and diagrams
│   ├── BACKUP.md                  # Backup and restore procedures
│   ├── CHECKLIST.md               # Production go-live checklist
│   ├── DEVOPS_HANDOVER.md         # DevOps engineer onboarding
│   ├── SECURITY_REVIEW.md         # Security audit and recommendations
│   └── TROUBLESHOOTING.md         # Common issues and fixes
│
├── .env.example                   # Environment variable template
├── .gitignore                     # Git ignore (excludes .env, volumes)
├── README.md                      # This file
├── DEPLOYMENT.md                  # Production deployment guide
└── ARCHITECTURE.md                # Shortcut link to docs/ARCHITECTURE.md
```

---

## 5. Installation (Local)

### Step 1: Clone the repository

```bash
git clone https://github.com/your-org/n8n-whatsapp-crm.git
cd n8n-whatsapp-crm
```

### Step 2: Create environment file

```bash
cp .env.example .env
```

### Step 3: Fill in required values

Open `.env` and set at minimum:

```env
N8N_ENCRYPTION_KEY=<generate with: openssl rand -hex 32>
N8N_BASIC_AUTH_PASSWORD=<strong password>
WEBHOOK_URL=http://localhost:5678
WHATSAPP_PHONE_NUMBER_ID=<from Meta Business>
WHATSAPP_ACCESS_TOKEN=<from Meta Business>
WHATSAPP_VERIFY_TOKEN=<your chosen secret>
CRM_API_URL=https://crm.yourdomain.com/api/automation/leads
CRM_API_TOKEN=<from Laravel>
```

---

## 6. Running Locally

```bash
# Navigate to docker directory
cd docker

# Start n8n
docker compose up -d

# View logs
docker compose logs -f n8n

# Check health
docker compose ps
```

n8n will be available at: **http://localhost:5678**

Login with the credentials set in `N8N_BASIC_AUTH_USER` / `N8N_BASIC_AUTH_PASSWORD`.

---

## 7. Import Workflow

1. Open n8n at http://localhost:5678
2. Log in
3. Click **"+"** (New Workflow) → **"Import from File"**
4. Select `workflow/workflow.json`
5. Click **Save**
6. Do **not** activate yet — configure credentials first

---

## 8. Configure Credentials

### WhatsApp Credential

1. n8n → **Credentials** → **Add Credential** → **WhatsApp Business Cloud API**
2. Fill in:
   - **Access Token:** `WHATSAPP_ACCESS_TOKEN` value from `.env`
   - **Phone Number ID:** `WHATSAPP_PHONE_NUMBER_ID` value

### Google Gemini Credential

1. n8n → **Credentials** → **Add Credential** → **Google PaLM API** (used for Gemini)
2. Fill in:
   - **API Key:** `GEMINI_API_KEY` value

### CRM API Token

- The CRM API token is passed as an HTTP header directly in the workflow using `{{ $env.CRM_API_TOKEN }}`.
- No separate credential is needed — it reads from the environment variable.

---

## 9. Webhook Setup

### Get your webhook URL

After starting n8n, your webhook URLs are:

```
POST (messages):     https://n8n.yourdomain.com/webhook/whatsapp-lead-capture
GET (verification):  https://n8n.yourdomain.com/webhook/whatsapp-lead-capture
```

### Register with Meta

1. Go to [Meta Business Manager](https://business.facebook.com)
2. Navigate to: **WhatsApp** → **Configuration** → **Webhooks**
3. Click **Edit**
4. Set **Callback URL:** `https://n8n.yourdomain.com/webhook/whatsapp-lead-capture`
5. Set **Verify Token:** Same value as `WHATSAPP_VERIFY_TOKEN` in your `.env`
6. Click **Verify and Save**
7. Subscribe to: **messages** field

### Activate workflow

Only after credentials and webhook are configured:

1. Open the workflow in n8n
2. Toggle **Active** (top-right switch)
3. Send a test WhatsApp message to your registered number

---

## 10. Testing

### Manual test sequence

Send these messages to your WhatsApp business number in order:

| Step | Send | Expected Bot Response |
|------|------|-----------------------|
| 1 | Any message | "Hello 👋 What is your name?" |
| 2 | Your name | "What is your company name?" |
| 3 | Company name | "What is your email address?" |
| 4 | Email address | "Which ride are you interested in?" |
| 5 | Ride selection | "Thanks! Your details have been saved." |

### Verify CRM

After step 5, check your Laravel CRM for:
- New Lead record
- Client record (upserted by phone)
- Follow-up record
- Audit trail entry

### Verify DataTable

In n8n → **Data** → **Tables** → `whatsapp_conversations`:
- Row for your phone number
- `state = idle`
- `status = synced`
- `completed = true`

### Test error path

1. Temporarily set `CRM_API_URL` to an invalid URL in `.env`
2. Restart n8n: `docker compose restart n8n`
3. Complete the conversation
4. Expect: "Sorry, we could not process your request. Please try again later."
5. Check DataTable: `status = sync_failed`, `error` field populated

---

## 11. Stopping & Updating

```bash
# Stop containers
docker compose down

# Stop and remove volumes (WARNING: deletes all data)
docker compose down -v

# Update n8n to latest version
docker compose pull
docker compose up -d

# Check current n8n version
docker exec n8n-whatsapp-crm n8n --version
```

---

## 12. Backup & Restore

See [docs/BACKUP.md](docs/BACKUP.md) for complete procedures.

**Quick backup:**

```bash
# Stop n8n first (recommended for consistent backup)
docker compose down

# Backup the data volume
docker run --rm \
  -v n8n_data:/source \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/n8n-backup-$(date +%Y%m%d-%H%M%S).tar.gz -C /source .

# Restart n8n
docker compose up -d
```

---

## Support & Contacts

| Role | Responsibility |
|------|----------------|
| Automation Developer | n8n workflow, DataTable schema, state machine |
| Laravel Developer | CRM API endpoint, lead creation logic |
| DevOps Engineer | Server, Docker, nginx, SSL, backups |

---

*Generated: 2026-07-08 | Workflow: WhatsApp Automation Phase 2 - Conversation State*
