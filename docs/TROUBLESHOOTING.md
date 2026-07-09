# Troubleshooting Guide — WhatsApp CRM Automation

---

## Quick Diagnostics

```bash
# Check container status
docker compose ps

# View live logs
docker compose logs -f n8n

# Check container health
docker inspect --format='{{.State.Health.Status}}' n8n-whatsapp-crm

# Check n8n API health
curl -s http://localhost:5678/healthz

# Check disk space
df -h

# Check memory
free -h
```

---

## 1. Webhook Failures

### Problem: Meta webhook verification fails (GET returns wrong value or times out)

**Symptoms:**
- Meta Business Manager shows "Failed" or "Could not validate callback URL"
- `curl` to webhook URL returns error or wrong challenge

**Diagnosis:**
```bash
# Test webhook URL manually
curl -v "https://n8n.yourdomain.com/webhook/whatsapp-lead-capture?hub.mode=subscribe&hub.verify_token=YOUR_VERIFY_TOKEN&hub.challenge=test123"
# Expected: test123 with HTTP 200
```

**Common causes and fixes:**

| Cause | Fix |
|-------|-----|
| `Webhook1` node is not active | Activate the workflow in n8n |
| `WHATSAPP_VERIFY_TOKEN` mismatch | Ensure exact match in `.env` and Meta Webhook settings |
| nginx SSL not configured | Check: `curl -I https://n8n.yourdomain.com` returns 200 |
| n8n container not running | `docker compose up -d` |
| Firewall blocking port 443 | `sudo ufw allow 443/tcp` |
| Workflow not saved | Save the workflow in n8n UI before activating |

---

### Problem: WhatsApp messages not arriving in n8n

**Symptoms:**
- Customer sends a message but no execution appears in n8n
- n8n execution history shows nothing

**Diagnosis:**
```bash
# Check n8n webhook is active
curl -s http://localhost:5678/api/v1/workflows \
  -H "Authorization: Basic $(echo -n admin:PASSWORD | base64)"

# Check nginx access logs
sudo tail -f /var/log/nginx/access.log

# Check n8n logs for incoming requests
docker compose logs n8n | grep -i webhook
```

**Fixes:**
- Verify webhook is subscribed to `messages` field in Meta
- Check that the workflow is **Active** (green toggle in n8n)
- Ensure the webhook path exactly matches: `whatsapp-lead-capture`
- Verify Meta → WhatsApp → Configuration → Webhook status is "Connected"

---

### Problem: Webhook receives messages but workflow crashes immediately

**Symptoms:**
- Execution appears in n8n but fails at first node
- Error: `Cannot read properties of undefined (reading 'text')`

**Cause:** WhatsApp sent a non-message event (status update, read receipt, delivery receipt).

**Fix:** The `Guard: Text Message Only` (If1) node handles this. Verify it is connected after the Webhook node and the condition is:
```
$json.body.entry[0].changes[0].value.messages?.[0]?.text?.body is not empty
```

---

## 2. CRM Failures

### Problem: CRM API call fails — `ECONNREFUSED` or `ETIMEDOUT`

**Symptoms:**
- Execution reaches `CRM: Submit Lead` node and fails
- Error message shown to customer: "Sorry, we could not process your request"
- DataTable row: `status=sync_failed`

**Diagnosis:**
```bash
# Test CRM API from n8n server
curl -X POST "${CRM_API_URL}" \
  -H "Authorization: Bearer ${CRM_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"phone":"test","name":"test","company":"test","email":"test@test.com","ride":"test","source":"whatsapp"}'
```

**Fixes:**

| Error | Fix |
|-------|-----|
| `ECONNREFUSED` | CRM server is down or unreachable. Check Laravel server status. |
| `ETIMEDOUT` | CRM response too slow. Increase `CRM_API_TIMEOUT_MS`. |
| `401 Unauthorized` | `CRM_API_TOKEN` is wrong or expired. Regenerate in Laravel. |
| `404 Not Found` | `CRM_API_URL` is wrong. Verify the endpoint path. |
| `422 Unprocessable` | Laravel validation failed. Check `error` field in DataTable. |
| `500 Internal` | Laravel error. Check Laravel logs on CRM server. |

---

### Problem: CRM creates duplicate leads

**Expected behavior:** Every submission creates a new Lead. This is by design.
**If clients are being duplicated:** Laravel's upsert logic is broken. Check the Laravel `automation/leads` controller — Client should upsert on `phone` field.

---

### Problem: CRM call succeeds but conversation state not updated to `idle`

**Cause:** `State: Mark Synced` (Update row(s)3) has wrong filter — it may be filtering all rows instead of the current one.

**Fix:** Verify the filter in `State: Mark Synced` uses `id == $('Route: By Conversation State').item.json.id` (not `success isTrue`).

---

## 3. WhatsApp Message Delivery Failures

### Problem: Bot replies go to wrong number or don't arrive

**Symptoms:**
- n8n execution succeeds but customer doesn't receive message
- Messages go to a different number

**Cause:** Hardcoded `recipientPhoneNumber` in WhatsApp send nodes.

**Fix:** Every WhatsApp send node must use dynamic expression:
```javascript
={{ '+' + $('Normalize: Extract Payload').first().json.phone }}
```
Not a hardcoded number like `+919422512747`.

---

### Problem: Error 131047 — "Message failed to send because more than 24 hours have passed"

**Cause:** Customer is outside the 24-hour conversation window.

**Fix:**
1. Short-term: Customer must send a message first to open the window.
2. Long-term: Implement WhatsApp approved message templates for re-engagement.

---

### Problem: Error 131030 — "Recipient phone number not in allowed list"

**Cause:** You are using the WhatsApp test number which only sends to verified numbers.

**Fix:** 
- In development: Add the customer's number to the test number's allowed list in Meta Business Manager.
- In production: Use a real WhatsApp Business number (not the test number).

---

## 4. Conversation State Issues

### Problem: Bot always asks "What is your name?" even for returning users

**Cause:** `Lookup: Conversation by Phone` node is missing or has hardcoded phone filter.

**Fix:** Verify the DataTable GET node between `Normalize: Extract Payload` and `Route: New or Existing` has dynamic filter:
```
phone == $json.phone
```

---

### Problem: Bot stores wrong data (e.g., email stored as name)

**Cause:** Conversation state is stuck. The customer's message is being interpreted as an answer to a different question.

**Fix:**
1. Go to n8n → Data → Tables → `whatsapp_conversations`
2. Find the row with the customer's phone
3. Manually set `state = initial`
4. Customer sends a new message to restart

---

### Problem: Conversation never completes — stuck at `waiting_ride`

**Cause:** CRM API is failing and state remains `waiting_ride`.

**Fix:**
1. Check the `error` field in the DataTable for the customer's row
2. Fix the underlying CRM issue
3. The next message the customer sends will retry the CRM submission

---

## 5. Docker Failures

### Problem: Container fails to start

```bash
# Check what went wrong
docker compose logs n8n

# Common error: N8N_ENCRYPTION_KEY is missing or empty
# Fix: ensure .env has a value for N8N_ENCRYPTION_KEY

# Common error: Port 5678 already in use
# Fix:
sudo lsof -i :5678
# Kill the conflicting process or change N8N_EXTERNAL_PORT in .env
```

---

### Problem: Container starts but healthcheck fails

```bash
# Check health status
docker inspect --format='{{json .State.Health}}' n8n-whatsapp-crm

# Test manually
docker exec n8n-whatsapp-crm wget -qO- http://localhost:5678/healthz

# Common cause: n8n needs more startup time
# Fix: Increase start_period in docker-compose.yml healthcheck
```

---

### Problem: Volume data lost after container restart

```bash
# Check if volume exists
docker volume ls | grep n8n_data

# If missing, it was deleted (e.g., docker compose down -v)
# Restore from backup:
./scripts/restore.sh backups/n8n-backup-YYYYMMDD.tar.gz
```

---

### Problem: n8n out of disk space

```bash
# Check disk usage
df -h
docker system df

# Clean up
docker image prune -f        # Remove old images
docker container prune -f    # Remove stopped containers
docker volume prune -f       # WARNING: removes unused volumes — DO NOT run if unsure

# Reduce execution log retention in .env:
EXECUTIONS_DATA_MAX_AGE=72   # Reduce from 168 to 72 hours
```

---

## 6. Credential Issues

### Problem: WhatsApp API returns 401 — Invalid access token

**Diagnosis:**
```bash
# Test token manually
curl -s "https://graph.facebook.com/v18.0/me?access_token=YOUR_TOKEN" | jq .
```

**Fixes:**
- System user tokens from Meta Business Manager do not expire (permanent tokens)
- Page tokens expire after ~60 days — do not use page tokens
- Regenerate: Meta Business → System Users → Generate Token → whatsapp_business_messaging permission

---

### Problem: Gemini API returns 403 — API key invalid

**Fix:**
1. Google AI Studio → API Keys → verify the key
2. Update `GEMINI_API_KEY` in `.env`
3. Restart n8n: `docker compose restart n8n`
4. Re-save the Google credential in n8n UI

---

### Problem: n8n credentials disappear after container restart

**Cause:** n8n volume is not mounted correctly, or `N8N_ENCRYPTION_KEY` changed.

**CRITICAL:** If `N8N_ENCRYPTION_KEY` changes, all stored credentials become unreadable.

**Fix:**
1. Verify the volume is mounted: `docker inspect n8n-whatsapp-crm | grep Mounts`
2. Ensure `N8N_ENCRYPTION_KEY` in `.env` is identical to what was used when credentials were created
3. Never change `N8N_ENCRYPTION_KEY` on an existing installation without migrating credentials first

---

## 7. Execution Failures

### Problem: Executions queue up but do not run

**Fix:**
```bash
# Check if n8n is in queue mode (should be main mode)
# Verify in .env:
EXECUTIONS_PROCESS=main

# Restart n8n
docker compose restart n8n
```

---

### Problem: Execution fails with "Cannot read property of undefined"

**Diagnosis:** Open the failed execution in n8n → click the failed node → inspect Input/Output data.

**Common causes:**

| Expression | Cause |
|------------|-------|
| `$json.body.entry[0]...` | WhatsApp payload structure changed |
| `$json.content.parts[0].text` | Gemini response format changed |
| `$('NodeName').first().json.x` | Referenced node has no output |

---

### Problem: n8n execution history is empty

**Cause:** `EXECUTIONS_DATA_PRUNE=true` with a short `EXECUTIONS_DATA_MAX_AGE`.

**Fix:** Increase `EXECUTIONS_DATA_MAX_AGE` in `.env` and restart.

---

## 8. SSL / HTTPS Issues

```bash
# Check SSL certificate status
sudo certbot certificates

# Force renewal
sudo certbot renew --force-renewal

# Check nginx SSL config
sudo nginx -t

# Check SSL from outside
curl -vI https://n8n.yourdomain.com 2>&1 | grep -E "SSL|TLS|cert|expire"

# Test webhook URL is reachable over HTTPS
curl -sk https://n8n.yourdomain.com/healthz
```

---

## Useful Log Commands

```bash
# n8n application logs
docker compose logs -f n8n

# n8n logs filtered for errors
docker compose logs n8n 2>&1 | grep -i error

# nginx access logs
sudo tail -f /var/log/nginx/access.log

# nginx error logs
sudo tail -f /var/log/nginx/error.log

# System logs
sudo journalctl -f -u nginx
sudo journalctl -f -u docker
```
