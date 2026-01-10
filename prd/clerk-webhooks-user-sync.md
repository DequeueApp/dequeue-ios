# PRD: Clerk Webhooks User Sync

**Status**: Ready for Review
**Author**: Claude
**Created**: 2026-01-10
**Last Updated**: 2026-01-10
**Issue**: TBD (Linear)

---

## Executive Summary

Implement Clerk webhook integration to sync user data to the backend when users sign up, update their profile, or delete their account. This enables proper relational data modeling with a `users` table that other tables can reference via foreign keys, replacing the current pattern of storing arbitrary `user_id` strings.

**Key Decisions:**
- **Webhook events**: Handle `user.created`, `user.updated`, `user.deleted`
- **User table**: Create proper `users` table in PostgreSQL
- **Foreign keys**: Convert `user_id` strings in `events`, `user_settings`, `attachment_files` to proper FK references
- **Soft delete**: Mark users as deleted rather than hard delete to preserve audit trail
- **Backfill**: One-time migration to sync existing Clerk users

---

## 1. Overview

### 1.1 Problem Statement

Currently, the backend has no concept of a "user" beyond the `user_id` claim extracted from Clerk JWTs. This causes several issues:

1. **No user metadata**: Cannot store email, name, profile image, or any user information
2. **No referential integrity**: `user_id` in `events`, `user_settings`, etc. is just an arbitrary string with no validation
3. **No lifecycle management**: If a user deletes their Clerk account, we have no way to know or handle cleanup
4. **No user queries**: Cannot list users, search by email, or perform any user-centric operations
5. **Orphaned data**: User data may persist indefinitely after account deletion

### 1.2 Proposed Solution

Implement Clerk webhook handlers in the `stacks-sync` backend to:

1. Receive webhook events when users are created, updated, or deleted in Clerk
2. Maintain a `users` table synchronized with Clerk's user data
3. Update existing tables to use proper foreign key relationships
4. Handle user deletion gracefully with soft deletes and data retention policies

### 1.3 Goals

- Maintain synchronized user records between Clerk and our database
- Enable proper relational data modeling with foreign key constraints
- Store essential user metadata (email, name, profile image)
- Handle user lifecycle events (creation, updates, deletion)
- Preserve audit trail and support data retention policies

### 1.4 Non-Goals

- Real-time user profile sync to iOS clients (JWT still used for auth)
- User management UI in the app (Clerk handles this)
- Custom user fields beyond what Clerk provides
- Multi-tenancy or organization support (future consideration)

---

## 2. Technical Design

### 2.1 Webhook Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           Clerk                                  │
│                                                                  │
│  Events: user.created, user.updated, user.deleted               │
└─────────────────────────┬───────────────────────────────────────┘
                          │ HTTPS POST (signed with HMAC-SHA256)
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    stacks-sync (Go Backend)                      │
│                                                                  │
│  POST /webhooks/clerk                                            │
│  ├── Verify signature (Svix webhook signature)                  │
│  ├── Parse event type and payload                               │
│  ├── Route to appropriate handler                               │
│  └── Return 200 OK (or error)                                   │
│                                                                  │
│  Handlers:                                                       │
│  ├── handleUserCreated()  → INSERT into users                   │
│  ├── handleUserUpdated()  → UPDATE users                        │
│  └── handleUserDeleted()  → Soft delete user                    │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                       PostgreSQL                                 │
│                                                                  │
│  users                                                           │
│  ├── id TEXT PRIMARY KEY           (Clerk user_id)              │
│  ├── email TEXT NOT NULL                                         │
│  ├── email_verified BOOLEAN                                      │
│  ├── first_name TEXT                                             │
│  ├── last_name TEXT                                              │
│  ├── image_url TEXT                                              │
│  ├── clerk_created_at TIMESTAMPTZ                               │
│  ├── created_at TIMESTAMPTZ                                      │
│  ├── updated_at TIMESTAMPTZ                                      │
│  ├── deleted_at TIMESTAMPTZ        (soft delete)                │
│  └── is_deleted BOOLEAN DEFAULT FALSE                           │
│                                                                  │
│  events                                                          │
│  └── user_id TEXT REFERENCES users(id)                          │
│                                                                  │
│  user_settings                                                   │
│  └── user_id TEXT REFERENCES users(id)                          │
│                                                                  │
│  attachment_files                                                │
│  └── user_id TEXT REFERENCES users(id)                          │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Database Schema

#### 2.2.1 New `users` Table

```sql
CREATE TABLE users (
    -- Primary identifier (Clerk user_id, e.g., "user_2abc123...")
    id TEXT PRIMARY KEY,

    -- Core user data from Clerk
    email TEXT NOT NULL,
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    first_name TEXT,
    last_name TEXT,
    image_url TEXT,

    -- Clerk metadata
    clerk_created_at TIMESTAMPTZ NOT NULL,
    clerk_updated_at TIMESTAMPTZ NOT NULL,

    -- Our metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Soft delete support
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMPTZ
);

-- Index for email lookups
CREATE INDEX idx_users_email ON users(email);

-- Index for listing active users
CREATE INDEX idx_users_active ON users(is_deleted) WHERE is_deleted = FALSE;
```

#### 2.2.2 Migration: Add Foreign Key Constraints

```sql
-- Step 1: Backfill users table from Clerk (run via script first)
-- See Section 2.6 for backfill procedure

-- Step 2: Add foreign key to events table
ALTER TABLE events
ADD CONSTRAINT fk_events_user
FOREIGN KEY (user_id) REFERENCES users(id)
ON DELETE RESTRICT;  -- Prevent deletion of users with events

-- Step 3: Add foreign key to user_settings table
ALTER TABLE user_settings
ADD CONSTRAINT fk_user_settings_user
FOREIGN KEY (user_id) REFERENCES users(id)
ON DELETE CASCADE;  -- Delete settings when user is deleted

-- Step 4: Add foreign key to attachment_files table
ALTER TABLE attachment_files
ADD CONSTRAINT fk_attachment_files_user
FOREIGN KEY (user_id) REFERENCES users(id)
ON DELETE RESTRICT;  -- Prevent deletion of users with attachments
```

### 2.3 Webhook Event Handling

#### 2.3.1 Clerk Webhook Payload Structure

```json
{
  "data": {
    "id": "user_2abc123def456",
    "email_addresses": [
      {
        "id": "idn_abc123",
        "email_address": "user@example.com",
        "verification": {
          "status": "verified"
        }
      }
    ],
    "primary_email_address_id": "idn_abc123",
    "first_name": "John",
    "last_name": "Doe",
    "image_url": "https://img.clerk.com/...",
    "created_at": 1704192600000,
    "updated_at": 1704192600000
  },
  "object": "event",
  "type": "user.created"
}
```

#### 2.3.2 Event Handlers

**`user.created`**
```go
func handleUserCreated(payload UserPayload) error {
    user := User{
        ID:              payload.ID,
        Email:           getPrimaryEmail(payload),
        EmailVerified:   isEmailVerified(payload),
        FirstName:       payload.FirstName,
        LastName:        payload.LastName,
        ImageURL:        payload.ImageURL,
        ClerkCreatedAt:  time.UnixMilli(payload.CreatedAt),
        ClerkUpdatedAt:  time.UnixMilli(payload.UpdatedAt),
    }

    // Upsert to handle duplicate webhook deliveries
    return db.UpsertUser(user)
}
```

**`user.updated`**
```go
func handleUserUpdated(payload UserPayload) error {
    updates := UserUpdates{
        Email:          getPrimaryEmail(payload),
        EmailVerified:  isEmailVerified(payload),
        FirstName:      payload.FirstName,
        LastName:       payload.LastName,
        ImageURL:       payload.ImageURL,
        ClerkUpdatedAt: time.UnixMilli(payload.UpdatedAt),
    }

    return db.UpdateUser(payload.ID, updates)
}
```

**`user.deleted`**
```go
func handleUserDeleted(payload UserDeletedPayload) error {
    // Soft delete - preserve audit trail
    return db.SoftDeleteUser(payload.ID)
}
```

### 2.4 Webhook Security

#### 2.4.1 Signature Verification

Clerk uses Svix for webhook delivery. Each request includes headers for verification:

```
svix-id: msg_abc123
svix-timestamp: 1704192600
svix-signature: v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=
```

Verification process:
```go
import "github.com/svix/svix-webhooks/go"

func verifyWebhook(r *http.Request, secret string) ([]byte, error) {
    wh, err := svix.NewWebhook(secret)
    if err != nil {
        return nil, err
    }

    payload, err := io.ReadAll(r.Body)
    if err != nil {
        return nil, err
    }

    err = wh.Verify(payload, r.Header)
    if err != nil {
        return nil, err
    }

    return payload, nil
}
```

#### 2.4.2 Configuration

```env
# Clerk webhook signing secret (from Clerk Dashboard > Webhooks)
CLERK_WEBHOOK_SECRET=whsec_abc123...
```

### 2.5 API Endpoint

```go
// POST /webhooks/clerk
func (h *WebhookHandler) HandleClerkWebhook(w http.ResponseWriter, r *http.Request) {
    // 1. Verify signature
    payload, err := verifyWebhook(r, h.clerkWebhookSecret)
    if err != nil {
        http.Error(w, "Invalid signature", http.StatusUnauthorized)
        return
    }

    // 2. Parse event
    var event ClerkEvent
    if err := json.Unmarshal(payload, &event); err != nil {
        http.Error(w, "Invalid payload", http.StatusBadRequest)
        return
    }

    // 3. Route to handler
    switch event.Type {
    case "user.created":
        err = h.handleUserCreated(event.Data)
    case "user.updated":
        err = h.handleUserUpdated(event.Data)
    case "user.deleted":
        err = h.handleUserDeleted(event.Data)
    default:
        // Ignore unknown event types (forward compatibility)
        w.WriteHeader(http.StatusOK)
        return
    }

    if err != nil {
        log.Error("Failed to handle webhook", "type", event.Type, "error", err)
        http.Error(w, "Internal error", http.StatusInternalServerError)
        return
    }

    w.WriteHeader(http.StatusOK)
}
```

### 2.6 Backfill Procedure

Before enabling foreign key constraints, existing users must be backfilled:

```go
// One-time migration script
func backfillUsersFromClerk(clerkClient *clerk.Client, db *sql.DB) error {
    // Paginate through all Clerk users
    params := clerk.ListUsersParams{
        Limit: 100,
    }

    for {
        users, err := clerkClient.Users.List(params)
        if err != nil {
            return err
        }

        for _, user := range users.Data {
            dbUser := clerkUserToDBUser(user)
            if err := db.UpsertUser(dbUser); err != nil {
                return err
            }
        }

        if !users.HasMore {
            break
        }
        params.AfterID = users.Data[len(users.Data)-1].ID
    }

    return nil
}
```

### 2.7 Idempotency

Webhooks may be delivered multiple times. All handlers must be idempotent:

1. **user.created**: Use `INSERT ... ON CONFLICT DO UPDATE` (upsert)
2. **user.updated**: Updates are naturally idempotent
3. **user.deleted**: Check if already deleted before updating

```sql
-- Upsert pattern for user.created
INSERT INTO users (id, email, email_verified, first_name, last_name, image_url,
                   clerk_created_at, clerk_updated_at, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), NOW())
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    email_verified = EXCLUDED.email_verified,
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    image_url = EXCLUDED.image_url,
    clerk_updated_at = EXCLUDED.clerk_updated_at,
    updated_at = NOW();
```

---

## 3. Implementation Phases

### Phase 1: Backend Webhook Infrastructure
**Repository**: stacks-sync

1. Add Svix Go SDK dependency
2. Create `users` table migration
3. Implement webhook endpoint (`POST /webhooks/clerk`)
4. Implement signature verification
5. Implement user.created handler
6. Implement user.updated handler
7. Implement user.deleted handler (soft delete)
8. Add webhook secret configuration
9. Write tests for webhook handlers

### Phase 2: Clerk Dashboard Configuration
1. Create webhook endpoint in Clerk Dashboard
2. Configure events: `user.created`, `user.updated`, `user.deleted`
3. Copy signing secret to backend configuration
4. Test webhook delivery with Clerk's test feature

### Phase 3: Backfill & Migration
1. Deploy webhook handlers (but don't enable FK constraints yet)
2. Run backfill script to sync existing Clerk users
3. Verify all existing `user_id` values have corresponding `users` records
4. Apply foreign key constraint migrations
5. Monitor for any constraint violations

### Phase 4: Cleanup & Monitoring
1. Add metrics for webhook processing (success/failure rates)
2. Add alerting for webhook failures
3. Implement user data retention policy (GDPR compliance)
4. Document webhook setup in README

---

## 4. Data Retention & Deletion

### 4.1 Soft Delete Policy

When a user deletes their Clerk account:

1. `user.deleted` webhook received
2. Set `is_deleted = TRUE` and `deleted_at = NOW()` on users record
3. Do NOT cascade delete to events (preserve audit trail)
4. Do NOT cascade delete to attachment_files (may need cleanup policy)
5. DO cascade delete to user_settings (no longer needed)

### 4.2 Data Retention Considerations

| Data Type | Retention Policy | Rationale |
|-----------|-----------------|-----------|
| Events | Indefinite (anonymize after 90 days) | Audit trail, analytics |
| User Settings | Delete immediately | Personal preferences, no longer needed |
| Attachment Files | 30 days, then cleanup | Allow grace period for reactivation |
| User Record | Soft delete, hard delete after 1 year | Legal/compliance requirements |

### 4.3 GDPR Compliance

For data deletion requests:
1. Soft delete user immediately
2. Anonymize user data in events (replace email with hash)
3. Schedule hard delete of user record after retention period
4. Delete attachments after 30-day grace period

---

## 5. Error Handling

### 5.1 Webhook Failures

| Scenario | Behavior |
|----------|----------|
| Invalid signature | Return 401, log warning |
| Invalid JSON payload | Return 400, log error |
| Unknown event type | Return 200, ignore (forward compatibility) |
| Database error | Return 500, Clerk will retry |
| Duplicate event | Handle idempotently, return 200 |

### 5.2 Retry Behavior

Clerk (via Svix) automatically retries failed webhooks with exponential backoff:
- Retry 1: 5 seconds
- Retry 2: 5 minutes
- Retry 3: 30 minutes
- Retry 4: 2 hours
- Retry 5: 8 hours

Return 5xx for transient errors (database issues) to trigger retry.
Return 4xx for permanent errors (bad payload) to prevent retry.

---

## 6. Testing

### 6.1 Unit Tests

```go
func TestHandleUserCreated(t *testing.T) {
    // Test successful user creation
    // Test duplicate user creation (idempotency)
    // Test missing required fields
}

func TestHandleUserUpdated(t *testing.T) {
    // Test successful update
    // Test update for non-existent user (should create)
    // Test partial updates
}

func TestHandleUserDeleted(t *testing.T) {
    // Test successful soft delete
    // Test delete for non-existent user
    // Test delete for already deleted user
}

func TestWebhookSignatureVerification(t *testing.T) {
    // Test valid signature
    // Test invalid signature
    // Test missing headers
    // Test expired timestamp
}
```

### 6.2 Integration Tests

1. Use Clerk's webhook test feature to send test events
2. Verify database state after each event type
3. Test webhook endpoint behind authentication/firewall

---

## 7. Configuration

### 7.1 Environment Variables

```env
# Clerk webhook signing secret
CLERK_WEBHOOK_SECRET=whsec_...

# Clerk API key (for backfill script)
CLERK_SECRET_KEY=sk_live_...
```

### 7.2 Clerk Dashboard Settings

1. Go to Clerk Dashboard > Webhooks
2. Add endpoint: `https://sync.ardonos.com/webhooks/clerk`
3. Select events:
   - `user.created`
   - `user.updated`
   - `user.deleted`
4. Copy Signing Secret to environment

---

## 8. Monitoring & Observability

### 8.1 Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `webhook_requests_total` | Counter | Total webhook requests by event type |
| `webhook_errors_total` | Counter | Failed webhook processing by error type |
| `webhook_latency_seconds` | Histogram | Webhook processing time |
| `users_total` | Gauge | Total users in database |
| `users_deleted_total` | Gauge | Soft-deleted users |

### 8.2 Logging

```json
{
  "level": "info",
  "msg": "Webhook processed",
  "event_type": "user.created",
  "user_id": "user_abc123",
  "duration_ms": 45
}
```

### 8.3 Alerting

- Alert if webhook error rate > 5% over 5 minutes
- Alert if no webhooks received in 24 hours (stale configuration)
- Alert if backfill script fails

---

## 9. Security Considerations

1. **Signature verification**: Always verify Svix signature before processing
2. **HTTPS only**: Webhook endpoint must be HTTPS
3. **Secret rotation**: Support rotating webhook secrets without downtime
4. **Rate limiting**: Consider rate limiting webhook endpoint
5. **IP allowlisting**: Optionally restrict to Clerk's IP ranges

---

## 10. Future Considerations

1. **Organization support**: Handle `organization.created`, `organization.updated` for B2B features
2. **Session webhooks**: Track `session.created`, `session.ended` for analytics
3. **Custom user metadata**: Sync Clerk public/private metadata
4. **User events in event stream**: Emit internal events for user changes to support client-side sync

---

## Appendix A: Clerk Webhook Event Reference

| Event | Trigger | Key Fields |
|-------|---------|------------|
| `user.created` | New user signs up | id, email, first_name, last_name, image_url, created_at |
| `user.updated` | User updates profile | id, email, first_name, last_name, image_url, updated_at |
| `user.deleted` | User deletes account | id, deleted |

Full documentation: https://clerk.com/docs/integrations/webhooks

---

## Appendix B: Existing Table Modifications

### events table
```sql
-- Current: user_id TEXT NOT NULL
-- After: user_id TEXT NOT NULL REFERENCES users(id)
```

### user_settings table
```sql
-- Current: user_id TEXT PRIMARY KEY
-- After: user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE
```

### attachment_files table (from attachments PRD)
```sql
-- Current: user_id TEXT NOT NULL
-- After: user_id TEXT NOT NULL REFERENCES users(id)
```
