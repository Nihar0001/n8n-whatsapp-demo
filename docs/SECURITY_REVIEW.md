# Security Review — WhatsApp CRM Automation

**Review Date:** 2026-07-08
**Reviewer:** Senior Automation Architect / Security Review

---

## Executive Summary

| Category | Current Status | Priority |
|----------|---------------|----------|
| Webhook Authentication | ❌ NOT IMPLEMENTED | P0 Critical |
| API Authentication | ❌ NOT IMPLEMENTED (in workflow) | P0 Critical |
| Hardcoded Secrets | ❌ PRESENT (require removal before production) | P0 Critical |
| Input Validation | ⚠️ PARTIAL | P1 High |
| Credential Exposure | ⚠️ WARNING | P1 High |
| Rate Limiting | ❌ NOT IMPLEMENTED | P1 High |
| HTTPS | ✅ Required and documented | OK |
| Basic Auth on n8n UI | ✅ Configured | OK |

---

## 1. Missing Authentication

### 1.1 — Webhook Signature Validation (P0 CRITICAL)

**Issue:** The `WA: Inbound Message Webhook` node accepts any POST request to `/webhook/whatsapp-lead-capture` without validating that it came from Meta. Anyone who discovers the webhook URL can POST fake WhatsApp events.

**Impact:**
- Fake leads created in CRM
- Conversation state corrupted
- Unnecessary API calls and costs

**WhatsApp Security Model:**
Meta signs every POST request with HMAC-SHA256 using your App Secret. The signature is in the `X-Hub-Signature-256` header.

**Required Fix — Add a Code node before `Guard: Text Message Only`:**

```javascript
// Node name: Validate: Webhook Signature
// Place between Webhook node and Guard: Text Message Only

const crypto = require('crypto');

const appSecret = $env.WHATSAPP_APP_SECRET;
const signature = $json.headers['x-hub-signature-256'];
const body = JSON.stringify($json.body);

if (!signature) {
  throw new Error('Missing X-Hub-Signature-256 header');
}

const expectedSignature = 'sha256=' + crypto
  .createHmac('sha256', appSecret)
  .update(body)
  .digest('hex');

if (signature !== expectedSignature) {
  throw new Error('Invalid webhook signature — request rejected');
}

return [{ json: $json }];
```

**Add to `.env.example`:**
```env
# WhatsApp App Secret (from Meta Business → App → Basic Settings → App Secret)
WHATSAPP_APP_SECRET=
```

---

### 1.2 — CRM API Authentication (P0 CRITICAL)

**Issue:** The current workflow JSON does not include an `Authorization` header in the CRM HTTP Request node. The Laravel endpoint accepts unauthenticated requests.

**Required Fix — Add header to `CRM: Submit Lead` node:**

```json
{
  "Authorization": "Bearer {{ $env.CRM_API_TOKEN }}"
}
```

**Laravel Middleware (for reference to Laravel developer):**

```php
// In Laravel api.php or routes
Route::middleware('auth:sanctum')->group(function () {
    Route::post('/automation/leads', [AutomationController::class, 'createLead']);
});
```

---

## 2. Missing Authorization

### 2.1 — n8n API Endpoint Exposure

**Issue:** n8n exposes a REST API at `/api/v1/`. If basic auth is disabled or weak, this API allows reading credentials, deleting workflows, etc.

**Fix:**
- `N8N_BASIC_AUTH_ACTIVE=true` (already configured)
- Use a strong password (minimum 16 characters, random)
- Consider IP allowlisting for n8n UI access in nginx:
  ```nginx
  location /api/ {
    allow YOUR_ADMIN_IP;
    deny all;
    proxy_pass http://127.0.0.1:5678;
  }
  ```

---

## 3. Hardcoded Secrets (Require Removal Before Production)

### Found in workflow.json (original):

| Location | Value | Risk |
|----------|-------|------|
| All WhatsApp send nodes | `recipientPhoneNumber: "+919422512747"` | All messages go to test number |
| `Get row(s)` filter | `phone == 919422512747` | Only looks up one phone |
| `HTTP Request [Debug]` URL | `https://advantageous-earleen-gripey.ngrok-free.dev/...` | ngrok URL exposed |
| `HTTP Request [CRM]` URL | `https://reopen-step-granny.ngrok-free.dev/...` | ngrok URL exposed |
| Credential IDs in JSON | `rK8y7vbcNDypfnvO`, `RH0vXDrIb2ZgCDLl` | Credential IDs in source |

**All of the above are replaced in the cleaned workflow with environment variables and dynamic expressions.**

### Action Required:

```bash
# Before committing workflow.json to Git, verify no hardcoded values:
grep -i "ngrok" workflow/workflow.json && echo "FAIL: ngrok URL found"
grep -i "919422512747" workflow/workflow.json && echo "FAIL: hardcoded phone found"
grep -i "rK8y7vb" workflow/workflow.json && echo "FAIL: credential ID found"
```

---

## 4. Credential Exposure

### 4.1 — n8n Credential IDs in Exported JSON

n8n workflow exports include credential IDs (not the actual secrets, but the internal reference IDs). These IDs alone are not a security risk, but they reveal internal n8n credential structure.

**Fix:**
- Strip credential IDs from workflow.json before committing to Git:
  The cleaned workflow uses environment variables, minimizing credential references.
- Store `workflow.json` in a private Git repository only.

### 4.2 — `.env` File Security

The `.env` file contains all secrets. It must never be committed to Git.

**Verify `.gitignore` includes:**
```
.env
*.env
backups/
```

**Set correct file permissions on server:**
```bash
chmod 600 /opt/n8n-whatsapp-crm/.env
chown $USER:$USER /opt/n8n-whatsapp-crm/.env
```

### 4.3 — N8N_ENCRYPTION_KEY

This key encrypts all credentials stored in n8n. If it is leaked:
- An attacker with database access can decrypt all stored API tokens.

**Best practices:**
- Never share this key over email, Slack, or chat.
- Store it in a password manager or secrets vault (HashiCorp Vault, AWS Secrets Manager).
- Never change this key on an existing installation without migrating credentials.

---

## 5. Input Validation

### 5.1 — Customer Input Is Not Validated Before CRM Submission

Customer responses to "What is your name?" etc. are stored and sent to CRM as-is.

**Current risks:**
- SQL injection if Laravel does not use parameterized queries (Laravel's Eloquent handles this)
- XSS in CRM UI if data is rendered without escaping (Laravel Blade escapes by default)
- Unusually long strings or special characters may cause CRM validation errors

**Recommended fix (in workflow Code node before CRM call):**

```javascript
// Sanitize collected fields
function sanitize(value, maxLength = 255) {
  if (!value || typeof value !== 'string') return null;
  return value.replace(/[<>\"']/g, '').substring(0, maxLength).trim();
}

return [{
  json: {
    phone: $json.phone,
    name: sanitize($json.name, 100),
    company: sanitize($json.company, 200),
    email: $json.email?.toLowerCase().trim().substring(0, 255),
    ride: sanitize($json.ride, 200),
    source: 'whatsapp'
  }
}];
```

### 5.2 — Email Format Validation

No email format validation exists before advancing from `waiting_email` state.

**Recommended fix — Add IF node after `State: Save Email → waiting_ride`:**

```javascript
// Condition: valid email format
/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test($json.email)
// TRUE: continue to waiting_ride
// FALSE: WA: "Please enter a valid email address." and stay in waiting_email
```

---

## 6. Rate Limiting

### 6.1 — No Rate Limiting on Webhook Endpoint

**Risk:** A bad actor can flood your webhook with requests, consuming CRM credits, WhatsApp messaging quota, and Gemini API quota.

**Recommended fixes:**

**Option A — Nginx rate limiting (recommended):**
```nginx
# Add to nginx.conf http block:
limit_req_zone $binary_remote_addr zone=webhook:10m rate=10r/s;

# Add to webhook location:
location /webhook/ {
    limit_req zone=webhook burst=20 nodelay;
    proxy_pass http://127.0.0.1:5678;
}
```

**Option B — Cloudflare (if using Cloudflare DNS):**
- Enable WAF rules for the webhook path
- Rate limit by IP to 30 requests/minute

### 6.2 — WhatsApp API Rate Limits

Meta enforces rate limits on outbound messages. Do not send more than:
- 1 message per second per phone number
- 1000 messages per day on test numbers

The current workflow (one reply per inbound message) stays well within these limits.

---

## 7. API Security

### 7.1 — HTTPS Only

All external communications must use HTTPS:
- ✅ n8n webhook URL: enforced via nginx SSL
- ✅ Meta WhatsApp API: always HTTPS
- ✅ Google Gemini API: always HTTPS
- ⚠️ CRM API: ensure `CRM_API_URL` uses `https://` — never `http://`

### 7.2 — CRM API Token Rotation

The `CRM_API_TOKEN` should be rotated every 90 days.

**Rotation procedure:**
1. Generate new token in Laravel
2. Update `CRM_API_TOKEN` in `.env`
3. Restart n8n: `docker compose restart n8n`
4. Test CRM API call works
5. Invalidate old token in Laravel

### 7.3 — WhatsApp Access Token

Use a **permanent system user token** from Meta Business Manager:
- System user tokens do NOT expire (unlike page tokens which expire after 60 days)
- Required permission: `whatsapp_business_messaging`
- Never use your personal Facebook access token

---

## 8. Security Best Practices Summary

| Practice | Status | Action Required |
|----------|--------|-----------------|
| Webhook HMAC signature validation | ❌ Missing | Add Code node to validate X-Hub-Signature-256 |
| CRM API bearer token | ❌ Missing in workflow | Add Authorization header using $env.CRM_API_TOKEN |
| HTTPS for all endpoints | ✅ Documented | Verify CRM_API_URL uses https:// |
| n8n UI password protection | ✅ Configured | Use strong password |
| No hardcoded secrets in workflow | ✅ Fixed | Verify with grep before deploying |
| .env not in Git | ✅ .gitignore | Verify before first push |
| N8N_ENCRYPTION_KEY backed up | ⚠️ Your responsibility | Store securely, separate from volume backup |
| Rate limiting on webhook | ❌ Missing | Add nginx limit_req |
| Input sanitization | ⚠️ Partial | Add Code node before CRM call |
| Email format validation | ❌ Missing | Add IF node in waiting_email state |
| Token rotation policy | ⚠️ Undocumented | Schedule 90-day rotation |
| Firewall: port 5678 closed | ✅ Documented | Verify with: nmap -p 5678 YOUR_SERVER_IP |
| SSH password auth disabled | ✅ Recommended | Set PasswordAuthentication no in sshd_config |
| Fail2ban installed | ✅ Recommended | Protects against brute force on port 22 |

---

## 9. WHATSAPP_APP_SECRET — Additional Variable Required

The webhook signature validation (see 1.1) requires a new environment variable:

```env
# Add to .env.example:
# WhatsApp App Secret for webhook signature validation
# Found at: Meta Business → Apps → Your App → Settings → Basic → App Secret
WHATSAPP_APP_SECRET=
```

This variable is already included in the `.env.example` generated for this project.

---

## 10. Recommended Security Roadmap

| Priority | Item | Effort |
|----------|------|--------|
| P0 | Implement webhook HMAC signature validation | 30 minutes |
| P0 | Add Authorization header to CRM API call | 5 minutes |
| P1 | Add nginx rate limiting on webhook path | 15 minutes |
| P1 | Add input sanitization Code node | 30 minutes |
| P1 | Add email format validation | 15 minutes |
| P2 | Set up 90-day token rotation schedule | Planning only |
| P2 | Configure n8n error workflow → Slack/email alert | 30 minutes |
| P3 | IP allowlist for n8n UI in nginx | 15 minutes |
| P3 | Migrate to PostgreSQL for better security/auditing | Half day |
