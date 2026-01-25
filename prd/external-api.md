# PRD: Dequeue External API

**Status**: Draft  
**Author**: Ardonos (with Victor)  
**Created**: 2026-01-25  
**Last Updated**: 2026-01-25  
**Issue**: TBD (Linear)

---

## Executive Summary

Add a public REST API to Dequeue enabling third-party integrations and AI assistants (like Ardonos) to interact with a user's tasks and stacks programmatically. The API exposes a clean, resource-oriented interface while the backend remains event-sourced internally.

**Key Decisions:**
- **API style**: RESTful resource-oriented (not event-sourced externally)
- **Auth**: API keys with scopes (built on top of Clerk user identity)
- **Deployment**: Separate API service or new routes in stacks-sync
- **Events**: API operations emit events internally (same as app)
- **Rate limiting**: Per-key limits to prevent abuse

---

## 1. Overview

### 1.1 Problem Statement

Dequeue currently has no programmatic access. Users cannot:
- Integrate Dequeue with other tools (Zapier, IFTTT, shortcuts)
- Let AI assistants manage their tasks
- Build custom automations or workflows
- Export/import data programmatically
- Use Dequeue as part of a larger productivity system

The iOS app is the only way to interact with Dequeue, limiting its utility for power users and integration scenarios.

### 1.2 Proposed Solution

Build a REST API that:
- Exposes core Dequeue operations (CRUD for stacks, tasks, tags)
- Uses API keys for authentication (tied to user accounts)
- Translates REST operations into internal events
- Returns data in standard JSON format
- Supports webhooks for real-time notifications (Phase 2)

### 1.3 Goals

- Enable AI assistants to fully manage a user's Dequeue data
- Provide a developer-friendly REST interface
- Maintain event-sourcing internally without exposing it
- Support OAuth for third-party app authorization (Phase 2)
- Keep the API simple—match what the app can do, no more

### 1.4 Non-Goals (v1)

- GraphQL (REST is simpler to start)
- Public developer portal (internal/trusted use first)
- Bulk operations beyond basic list endpoints
- Real-time streaming (WebSockets for API clients)
- Multi-user/team features
- Billing/usage metering

---

## 2. User Stories

### 2.1 Primary User Stories

1. **As Victor**, I want Ardonos to create tasks for me, so I can capture ideas hands-free.
2. **As a user**, I want to generate an API key in settings, so I can authorize integrations.
3. **As a user**, I want to revoke API keys, so I can disable compromised integrations.
4. **As a developer**, I want clear API docs, so I can build integrations quickly.
5. **As an AI assistant**, I want to list a user's stacks, so I can help them organize.
6. **As an AI assistant**, I want to add tasks to a specific stack, so I can help capture work.
7. **As an AI assistant**, I want to mark tasks complete, so I can help track progress.
8. **As a user**, I want to see which integrations accessed my data, so I have visibility.

### 2.2 Ardonos-Specific Stories

1. **As Ardonos**, I want to query Victor's active stacks to understand his current priorities.
2. **As Ardonos**, I want to add tasks with notes/context from our conversations.
3. **As Ardonos**, I want to move tasks between stacks based on Victor's instructions.
4. **As Ardonos**, I want to complete tasks when Victor tells me something is done.
5. **As Ardonos**, I want to create new stacks for emerging projects.

---

## 3. API Design

### 3.1 Design Principles

1. **Resource-oriented**: `/stacks`, `/stacks/{id}/tasks` — not event-based
2. **RESTful verbs**: GET, POST, PUT, PATCH, DELETE
3. **JSON everywhere**: Request and response bodies
4. **Consistent errors**: Standard error format with codes
5. **Idempotent where possible**: PUT/DELETE are idempotent
6. **Pagination**: Cursor-based for lists
7. **Filtering**: Query params for common filters

### 3.2 Why Not Expose Events?

The internal event-sourced architecture is an implementation detail. Exposing it externally would:
- **Confuse developers**: "What events do I send to create a task?"
- **Couple clients to internals**: Schema changes break integrations
- **Complicate versioning**: Event schemas are harder to version than REST
- **Increase learning curve**: REST is universally understood

Instead, the API layer accepts REST requests and emits events internally, exactly like the iOS app does. External developers get a clean interface; internal consistency is maintained.

### 3.3 Base URL

```
https://api.dequeue.app/v1
```

Or initially:
```
https://sync-service.fly.dev/apps/dequeue/api/v1
```

### 3.4 Authentication

#### API Keys (v1)

```
Authorization: Bearer dq_live_xxxxxxxxxxxxxxxxxxxx
```

- Keys prefixed with `dq_live_` (production) or `dq_test_` (sandbox)
- Keys tied to a specific user account
- Keys have scopes limiting access (e.g., `read`, `write`, `admin`)
- Keys can be rotated/revoked from app settings
- Rate limited per key (e.g., 100 req/min)

#### OAuth 2.0 (v2 — Future)

For third-party apps that need to act on behalf of users:
- Authorization code flow
- Scopes: `stacks:read`, `stacks:write`, `tasks:read`, `tasks:write`
- Refresh tokens for long-lived access

### 3.5 Endpoints

#### Stacks

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/stacks` | List all stacks |
| POST | `/stacks` | Create a stack |
| GET | `/stacks/{id}` | Get a stack |
| PATCH | `/stacks/{id}` | Update a stack |
| DELETE | `/stacks/{id}` | Archive/delete a stack |

#### Tasks

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/stacks/{stackId}/tasks` | List tasks in a stack |
| POST | `/stacks/{stackId}/tasks` | Create a task |
| GET | `/tasks/{id}` | Get a task |
| PATCH | `/tasks/{id}` | Update a task |
| DELETE | `/tasks/{id}` | Delete a task |
| POST | `/tasks/{id}/complete` | Mark task complete |
| POST | `/tasks/{id}/uncomplete` | Mark task incomplete |
| POST | `/tasks/{id}/move` | Move to different stack |

#### Tags

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/tags` | List all tags |
| POST | `/tags` | Create a tag |
| PATCH | `/tags/{id}` | Update a tag |
| DELETE | `/tags/{id}` | Delete a tag |

#### User

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/me` | Get current user info |
| GET | `/me/api-keys` | List API keys |
| POST | `/me/api-keys` | Create API key |
| DELETE | `/me/api-keys/{id}` | Revoke API key |

### 3.6 Request/Response Examples

#### Create a Task

```http
POST /v1/stacks/stk_abc123/tasks
Authorization: Bearer dq_live_xxxx
Content-Type: application/json

{
  "title": "Review Q1 budget proposal",
  "notes": "From conversation with Ardonos on 2026-01-25",
  "priority": 2,
  "dueDate": "2026-01-30T17:00:00Z",
  "tags": ["work", "finance"]
}
```

Response:
```json
{
  "id": "tsk_def456",
  "stackId": "stk_abc123",
  "title": "Review Q1 budget proposal",
  "notes": "From conversation with Ardonos on 2026-01-25",
  "priority": 2,
  "dueDate": "2026-01-30T17:00:00Z",
  "tags": ["work", "finance"],
  "status": "active",
  "createdAt": "2026-01-25T02:00:00Z",
  "updatedAt": "2026-01-25T02:00:00Z"
}
```

#### List Stacks

```http
GET /v1/stacks?status=active&limit=20
Authorization: Bearer dq_live_xxxx
```

Response:
```json
{
  "data": [
    {
      "id": "stk_abc123",
      "title": "Texture Q1 Planning",
      "status": "active",
      "taskCount": 12,
      "completedCount": 5,
      "tags": ["work", "texture"],
      "createdAt": "2026-01-10T10:00:00Z",
      "updatedAt": "2026-01-24T15:30:00Z"
    }
  ],
  "pagination": {
    "cursor": "eyJpZCI6InN0a19hYmMxMjMifQ",
    "hasMore": true
  }
}
```

#### Error Response

```json
{
  "error": {
    "code": "STACK_NOT_FOUND",
    "message": "Stack with id 'stk_invalid' not found",
    "status": 404
  }
}
```

### 3.7 Rate Limiting

Headers on every response:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1706148000
```

When exceeded:
```json
{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Rate limit exceeded. Try again in 45 seconds.",
    "status": 429
  }
}
```

---

## 4. Technical Architecture

### 4.1 Deployment Options

#### Option A: Extend stacks-sync (Recommended for v1)

Add API routes to the existing Go service:
```
/apps/dequeue/api/v1/stacks
/apps/dequeue/api/v1/tasks
```

**Pros:**
- Single deployment
- Shared database connection
- Can emit events directly

**Cons:**
- Mixes generic sync with Dequeue-specific logic
- Go isn't ideal for rapid API iteration

#### Option B: Separate API Service

New service (Node.js/TypeScript or Go):
```
api.dequeue.app → API service → stacks-sync (for events)
```

**Pros:**
- Clean separation
- Can use TypeScript for faster iteration
- Independent scaling

**Cons:**
- Another service to deploy/monitor
- Need to call stacks-sync for event emission

**Recommendation**: Start with Option A (extend stacks-sync) for v1. If API grows complex, extract to separate service.

### 4.2 Internal Event Flow

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   API       │      │   Event     │      │   Event     │
│   Request   │ ──── │   Emitter   │ ──── │   Store     │
│  (REST)     │      │             │      │  (Postgres) │
└─────────────┘      └─────────────┘      └─────────────┘
       │                                         │
       │              ┌─────────────┐            │
       └──────────── │   Query     │ ───────────┘
         (reads)      │   Layer     │   (projections)
                      └─────────────┘
```

1. API receives `POST /stacks` request
2. API validates input, creates `stack.created` event
3. Event stored in PostgreSQL (same as app events)
4. API queries projection tables for response
5. WebSocket notifies connected clients (iOS app)

### 4.3 API Key Storage

```sql
CREATE TABLE api_keys (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,               -- "Ardonos", "Zapier"
    key_hash TEXT NOT NULL,           -- bcrypt hash of key
    key_prefix TEXT NOT NULL,         -- "dq_live_abc" for display
    scopes TEXT[] NOT NULL,           -- ['read', 'write']
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ
);

CREATE INDEX idx_api_keys_user ON api_keys(user_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_api_keys_prefix ON api_keys(key_prefix);
```

Key format: `dq_live_` + 32 random alphanumeric chars
Only the hash is stored; full key shown once on creation.

### 4.4 Clerk Integration

Clerk handles user authentication for the iOS app. For API keys:

1. **Key creation**: User authenticated via Clerk in app → creates API key
2. **Key validation**: API receives key → looks up in `api_keys` table → gets `user_id`
3. **No Clerk on API requests**: API keys bypass Clerk entirely (simpler, faster)

If we add OAuth later, Clerk could potentially handle the OAuth flow, but for v1 API keys, Clerk is only involved when managing keys from the app.

### 4.5 Scopes

| Scope | Permissions |
|-------|-------------|
| `read` | GET on all endpoints |
| `write` | POST, PATCH, DELETE on stacks/tasks/tags |
| `admin` | Manage API keys, account settings |

Default key gets `read` + `write`. `admin` must be explicitly granted.

---

## 5. Implementation Phases

### Phase 1: Core API + API Keys (MVP)

**Backend:**
- Add `api_keys` table
- Implement key generation (random + bcrypt)
- Implement key validation middleware
- Add `/stacks` CRUD endpoints
- Add `/stacks/{id}/tasks` CRUD endpoints
- Add `/tasks/{id}/complete` and `/move` actions
- Emit events for all mutations
- Basic rate limiting (in-memory or Redis)

**iOS App:**
- Add API Keys section in Settings
- Show existing keys (name, prefix, created, last used)
- Create new key (shows full key once)
- Revoke key with confirmation

**Ardonos Integration:**
- Store Victor's API key securely
- Build Dequeue skill for task management
- Test core workflows

### Phase 2: Tags + Enhanced Queries

- Add `/tags` endpoints
- Add filtering: `GET /tasks?status=active&tag=work`
- Add sorting: `?sort=dueDate&order=asc`
- Add search: `?q=budget`
- Improve pagination

### Phase 3: Webhooks

- User registers webhook URLs
- Events trigger HTTP callbacks
- Retry logic with exponential backoff
- Webhook signature verification

### Phase 4: OAuth 2.0

- Authorization code flow implementation
- Third-party app registration
- Consent screen
- Token refresh

### Phase 5: Developer Portal

- Public API documentation
- Interactive API explorer
- Rate limit dashboard
- Webhook logs

---

## 6. Security Considerations

### 6.1 API Key Security

- Keys generated with cryptographically secure random bytes
- Only bcrypt hash stored in database
- Full key shown exactly once on creation
- Keys can be scoped to limit damage if leaked
- Keys expire (optional) or can be revoked
- Rate limiting prevents brute force

### 6.2 Data Access

- API keys tied to single user; cannot access other users' data
- All queries filter by `user_id` from validated key
- No admin API for cross-user access

### 6.3 Transport

- HTTPS only (redirect HTTP)
- TLS 1.2+ required

### 6.4 Audit Logging

- Log all API requests with key prefix (not full key)
- Track `last_used_at` per key
- Future: full audit trail for compliance

---

## 7. Open Questions

| # | Question | Options | Notes |
|---|----------|---------|-------|
| 1 | API key prefix format | `dq_live_` vs `dequeue_` vs `dk_` | Shorter is nicer, but clarity matters |
| 2 | Rate limit storage | In-memory vs Redis | Redis if multi-instance, memory for v1 |
| 3 | Soft vs hard delete for tasks | Soft delete (archived) vs permanent | Match app behavior |
| 4 | Event attribution | Mark events as "via API" | Useful for debugging sync issues |
| 5 | Bulk operations | `/tasks/bulk` for batch create | Defer to v2 unless needed |
| 6 | Webhook secret rotation | Allow multiple active secrets | Standard practice for zero-downtime rotation |

---

## 8. Success Metrics

- Ardonos can create a task via API
- Ardonos can list Victor's stacks and tasks
- Task created via API syncs to iOS app within 5 seconds
- API key creation works from iOS settings
- 99.9% API uptime
- P95 latency < 200ms for read operations

---

## 9. Dependencies

- stacks-sync backend (event storage, WebSocket notifications)
- iOS app settings infrastructure
- Secure storage for Ardonos API key (Clawdbot secrets)

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| API key leaked | High | Scopes limit damage; easy revocation; audit logs |
| Rate limiting bypassed | Medium | Per-key + per-IP limits; abuse detection |
| Event sync conflicts | Medium | Same conflict resolution as app (LWW) |
| Scope creep | Medium | Strict v1 scope; defer OAuth/webhooks |
| Performance under load | Medium | Rate limits; caching; horizontal scaling |

---

## Appendix A: Alternative Auth Approaches Considered

### Clerk JWT Passthrough

Use Clerk-issued JWTs directly for API auth.

**Pros:** No custom key management; leverages existing auth
**Cons:** JWTs are short-lived (need refresh); not ideal for server-to-server; Clerk doesn't support API key generation natively

### Clerk Organizations + M2M

Use Clerk Organizations to model "integrations" as org members.

**Pros:** Built on Clerk
**Cons:** Overcomplicates the model; Organizations are for humans, not bots

### Auth0/Okta M2M

Use a dedicated identity provider with M2M grants.

**Pros:** Industry standard; robust
**Cons:** Another vendor; overkill for v1

**Decision:** Custom API keys are simpler for v1. Can add OAuth later for third-party apps.

---

## Appendix B: Ardonos Integration Example

Once API is live, Ardonos uses it like this:

```bash
# List Victor's active stacks
curl -H "Authorization: Bearer $DEQUEUE_API_KEY" \
  https://api.dequeue.app/v1/stacks?status=active

# Create a task in "Inbox" stack
curl -X POST \
  -H "Authorization: Bearer $DEQUEUE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"title": "Call dentist to reschedule", "notes": "Victor mentioned this at 2pm"}' \
  https://api.dequeue.app/v1/stacks/stk_inbox/tasks
```

A Clawdbot skill wraps these calls:

```markdown
## Dequeue Skill

Commands:
- `dequeue list stacks` → GET /stacks
- `dequeue list tasks [stack]` → GET /stacks/{id}/tasks
- `dequeue add task [title] to [stack]` → POST /stacks/{id}/tasks
- `dequeue complete [task]` → POST /tasks/{id}/complete
```

---

## Appendix C: Comparison with Similar APIs

| App | Auth | Style | Notes |
|-----|------|-------|-------|
| Todoist | API keys + OAuth | REST | Good model for simplicity |
| Things | None (no API) | — | Lost opportunity |
| Linear | API keys + OAuth | GraphQL | Powerful but complex |
| Notion | API keys + OAuth | REST | Well-documented, good example |
| Asana | OAuth + PAT | REST | Personal Access Tokens like API keys |

Dequeue should follow Todoist/Notion patterns: start with API keys, add OAuth when third-party demand exists.
