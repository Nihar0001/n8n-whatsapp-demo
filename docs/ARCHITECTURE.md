# Architecture — WhatsApp CRM Automation

---

## 1. System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         EXTERNAL SERVICES                               │
│                                                                         │
│  ┌─────────────┐   WhatsApp   ┌──────────────┐   HTTPS   ┌──────────┐  │
│  │  Customer   │◄────────────►│ Meta Cloud   │◄─────────►│  n8n     │  │
│  │  (Phone)    │              │     API      │           │ (Docker) │  │
│  └─────────────┘              └──────────────┘           └────┬─────┘  │
│                                                               │        │
│  ┌─────────────────────────────────────────────────────┐     │        │
│  │                       n8n Server                    │     │        │
│  │  ┌─────────────────────────────────────────────┐   │     │        │
│  │  │  Workflow: WhatsApp Lead Capture             │   │     │        │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  │   │     │        │
│  │  │  │ Webhook  │  │  State   │  │   CRM    │  │   │     │        │
│  │  │  │ Handler  │→ │ Machine  │→ │   Call   │  │   │     │        │
│  │  │  └──────────┘  └──────────┘  └────┬─────┘  │   │     │        │
│  │  └─────────────────────────────────── │ ───────┘   │     │        │
│  │                                        │            │     │        │
│  │  ┌──────────────────────┐              │            │     │        │
│  │  │  DataTable           │              │            │     │        │
│  │  │  whatsapp_convs      │              │            │     │        │
│  │  └──────────────────────┘              │            │     │        │
│  └────────────────────────────────────────│────────────┘     │        │
│                                           │                  │        │
│  ┌────────────────────────────────────────▼──────────────┐   │        │
│  │                  Laravel CRM Server                    │   │        │
│  │  POST /api/automation/leads                            │   │        │
│  │  Creates: Lead + Client (upsert) + Follow-up + Audit  │   │        │
│  └────────────────────────────────────────────────────────┘   │        │
│                                                                         │
│  ┌─────────────────────────────────────────────────────┐              │
│  │  Google Gemini API (optional AI enrichment path)    │              │
│  └─────────────────────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Network Architecture

```
Internet
    │
    ▼ :443 (HTTPS)
┌─────────────────┐
│  Nginx           │  Reverse proxy + SSL termination
│  n8n.domain.com  │  Certbot auto-renew (Let's Encrypt)
└────────┬────────┘
         │ :5678 (internal only)
         ▼
┌─────────────────┐
│  Docker Network  │  n8n_network (bridge)
│  ┌───────────┐   │
│  │   n8n     │   │  Container: n8n-whatsapp-crm
│  │  :5678    │   │  Volume: n8n_data → /home/node/.n8n
│  └───────────┘   │
└─────────────────┘
         │
         ▼ :443 (HTTPS outbound)
┌─────────────────────────────────────┐
│  External APIs                      │
│  • Meta WhatsApp Cloud API          │
│  • Laravel CRM API                  │
│  • Google Gemini API                │
└─────────────────────────────────────┘
```

---

## 3. Workflow Execution Flow

### Path A — Webhook Verification (one-time during setup)

```
Meta Platform                n8n
     │                        │
     │── GET /webhook/... ───►│
     │    ?hub.mode=subscribe  │
     │    ?hub.verify_token=X  │  Webhook1 node
     │    ?hub.challenge=Y     │       │
     │                        │  Respond to Webhook
     │◄─── Y (challenge) ─────│       │
     │    HTTP 200             │  (returns hub.challenge verbatim)
```

### Path B — Message Processing (every inbound WhatsApp message)

```
Customer                Meta API               n8n Webhook
   │                       │                      │
   │── WA message ─────────►                      │
   │                       │── POST /webhook ─────►│
   │                       │                      │ Webhook node
   │                       │                      │   │
   │                       │                      │ Guard: Text Message Only (If1)
   │                       │                      │   │ FALSE: stop (silently)
   │                       │                      │   │ TRUE: continue
   │                       │                      │   │
   │                       │                      │ Normalize Payload (Set)
   │                       │                      │ {source, name, phone, message}
   │                       │                      │   │
   │                       │                      │ Lookup Conversation by Phone
   │                       │                      │ (DataTable GET: phone==$json.phone)
   │                       │                      │   │
   │                       │                      │ Conversation Exists? (If2)
   │                       │                      │   │ FALSE: Insert row
   │                       │                      │   │ TRUE: continue
   │                       │                      │   │
   │                       │                      │ Route by Conversation State (Switch)
   │                       │                      │   │
   │                       │         ┌────────────┼────────────┬────────────┬───────────┐
   │                       │         │            │            │            │           │
   │                       │      initial    wait_name    wait_comp    wait_email  wait_ride
   │                       │         │            │            │            │           │
   │                       │     Set state   Save name   Save comp    Save email  Save ride
   │                       │     →wait_name  →wait_comp  →wait_email  →wait_ride  Call CRM
   │                       │         │            │            │            │           │
   │                       │     Ask Name   Ask Company  Ask Email    Ask Ride    ┌──┴──┐
   │                       │     (WA msg)   (WA msg)    (WA msg)    (WA msg) Success  Error
   │◄── WA reply ──────────│         │            │            │            │       │      │
                                                                          Mark   Mark
                                                                          synced failed
                                                                            │      │
                                                                        Thanks  Sorry
                                                                        (WA)    (WA)
```

---

## 4. Conversation State Machine

```
                     ┌─────────────┐
                     │   idle      │◄──────── CRM success + state=idle
                     └──────┬──────┘
                            │ (new message received when idle/no record)
                            ▼
                     ┌─────────────┐
                     │   initial   │
                     │  (row created│
                     │   or idle)  │
                     └──────┬──────┘
                            │ state set → waiting_name
                            │ WA: "What is your name?"
                            ▼
                     ┌──────────────────┐
                     │  waiting_name    │
                     │  (expects: name) │
                     └──────┬───────────┘
                            │ save name → state → waiting_company
                            │ WA: "What is your company?"
                            ▼
                     ┌──────────────────────┐
                     │  waiting_company     │
                     │  (expects: company)  │
                     └──────┬───────────────┘
                            │ save company → state → waiting_email
                            │ WA: "What is your email?"
                            ▼
                     ┌──────────────────────┐
                     │  waiting_email       │
                     │  (expects: email)    │
                     └──────┬───────────────┘
                            │ save email → state → waiting_ride
                            │ WA: "Which ride are you interested in?"
                            ▼
                     ┌──────────────────────┐
                     │  waiting_ride        │
                     │  (expects: ride)     │
                     └──────┬───────────────┘
                            │ save ride → call CRM API
                            │
              ┌─────────────┴─────────────┐
              │ SUCCESS                   │ ERROR
              ▼                           ▼
       state → idle                state stays waiting_ride
       status → synced             status → sync_failed
       WA: "Thanks!"               WA: "Sorry, try again"
                                   error field populated
```

### State Expiry (TTL)

If `updated_at` is older than `CONVERSATION_TTL_HOURS` (default: 24h), the conversation resets to `initial` on the next message. This prevents stale conversations from misinterpreting new messages.

---

## 5. CRM Integration

### Request

```
POST {CRM_API_URL}
Authorization: Bearer {CRM_API_TOKEN}
Content-Type: application/json

{
  "phone":   "919422512747",      // WhatsApp wa_id (no + prefix)
  "name":    "Customer Name",
  "company": "Company Name",
  "email":   "customer@email.com",
  "ride":    "Selected ride option",
  "source":  "whatsapp",
  "message": "original last message"
}
```

### Expected Response

```json
// Success
{ "success": true, "lead_id": 123 }

// Error
{ "message": "Validation failed: email is invalid" }
```

### What Laravel Creates Per Request

| Record | Behavior |
|--------|----------|
| Lead | Always new (no deduplication) |
| Client | Upserted by phone number |
| Follow-up | Always new |
| Audit Trail | Always new |

---

## 6. WhatsApp Integration

### Inbound (Meta → n8n)

```
Meta Cloud API
POST https://n8n.yourdomain.com/webhook/whatsapp-lead-capture
Content-Type: application/json
X-Hub-Signature-256: sha256=...

{
  "entry": [{
    "changes": [{
      "value": {
        "messages": [{ "text": { "body": "Hello" } }],
        "contacts": [{ "wa_id": "919422512747", "profile": { "name": "John" } }]
      }
    }]
  }]
}
```

### Outbound (n8n → Meta → Customer)

```
POST https://graph.facebook.com/v18.0/{PHONE_NUMBER_ID}/messages
Authorization: Bearer {WHATSAPP_ACCESS_TOKEN}
Content-Type: application/json

{
  "messaging_product": "whatsapp",
  "to": "919422512747",
  "type": "text",
  "text": { "body": "Hello 👋 What is your name?" }
}
```

---

## 7. AI Integration (Optional Path)

The Gemini AI node provides one-shot extraction of lead data from a complex message. This is used in the secondary flow path (currently marked as optional/future).

**Model:** `models/gemini-2.5-flash`
**Credential:** Google PaLM API (used for Gemini)
**Input:** Customer's raw WhatsApp message
**Output schema:**

```json
{
  "has_request": true,
  "customer_name": "John Doe",
  "service": "Airport Transfer",
  "pickup": "Hotel Grand",
  "destination": "Mumbai Airport T2",
  "travel_date": "2026-07-15",
  "travel_time": "06:00",
  "passengers": 2,
  "special_requirements": "Wheelchair accessible",
  "summary": "Airport transfer for 2 passengers on July 15",
  "original_message": "..."
}
```

---

## 8. DataTable Schema

**Table name:** `whatsapp_conversations`
**DataTable ID:** `xmAUd6G9ZmSFA0r9` (n8n internal)

| Column | Type | Description |
|--------|------|-------------|
| `id` | auto number | Primary key (auto-generated by n8n) |
| `phone` | string | Customer WhatsApp ID (wa_id, no + prefix) |
| `name` | string | Collected during waiting_name state |
| `company` | string | Collected during waiting_company state |
| `email` | string | Collected during waiting_email state |
| `ride` | string | Collected during waiting_ride state |
| `state` | string | Current FSM state |
| `status` | string | `active` / `synced` / `sync_failed` |
| `updated_at` | dateTime | Timestamp of last state update |
| `synced_at` | dateTime | Timestamp of successful CRM sync |
| `crm_lead_id` | string | Lead ID returned by Laravel API |
| `completed` | boolean | True when full flow completed |
| `success` | boolean | True when CRM sync succeeded |
| `error` | string | Error message from failed CRM call |

---

## 9. Failure Flow

```
Any DataTable Write Failure
         │
         ▼
    [No error branch configured — silent fail]
    → Execution stops without customer notification
    → n8n execution log records error
    → (Recommended: add error workflow → Slack alert)

CRM API Failure
         │
         ▼
    Update row(s) — Mark Error
    status=sync_failed, error={message}
         │
         ▼
    WA: "Sorry, we could not process your request"
         │
         ▼
    Customer can retry by sending next message
    (state remains waiting_ride, row persists)
```

---

## 10. Retry Flow

```
CRM HTTP Request fails (network/5xx)
         │
         ▼ retryOnFail: true (3 attempts, 1s delay)
         │
    Attempt 1 ─── fail ───►
    Attempt 2 ─── fail ───►
    Attempt 3 ─── fail ───►
         │
         ▼
    Error branch → Update row + WA apology
```

---

## 11. Node Inventory (Production Workflow)

| Node Name | Type | Purpose |
|-----------|------|---------|
| WA: Inbound Message Webhook | webhook | Receives WhatsApp POST events |
| Guard: Text Message Only | if | Drops non-text events |
| Normalize: Extract Payload | set | Flattens WhatsApp payload |
| Lookup: Conversation by Phone | dataTable | Gets existing row by phone |
| Route: New or Existing | if | Branches on row existence |
| Init: Create Conversation Row | dataTable | Inserts new row with state=initial |
| Route: By Conversation State | switch | Dispatches to state handler |
| State: initial → Set waiting_name | dataTable | Updates state |
| WA: Ask Name | whatsApp | Sends name question |
| State: Save Name → waiting_company | dataTable | Saves name, advances state |
| WA: Ask Company | whatsApp | Sends company question |
| State: Save Company → waiting_email | dataTable | Saves company, advances state |
| WA: Ask Email | whatsApp | Sends email question |
| State: Save Email → waiting_ride | dataTable | Saves email, advances state |
| WA: Ask Ride | whatsApp | Sends ride options question |
| State: Save Ride | dataTable | Saves ride selection |
| CRM: Submit Lead | httpRequest | POSTs to Laravel API |
| State: Mark Synced | dataTable | Updates row on success |
| WA: Confirm Success | whatsApp | Sends thank-you message |
| State: Mark Failed | dataTable | Records error on failure |
| WA: Send Error Message | whatsApp | Sends apology message |
| WA: Verify Token Webhook | webhook | Handles GET verification |
| WA: Respond to Verification | respondToWebhook | Returns hub.challenge |
