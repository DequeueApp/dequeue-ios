# PRD: Dequeue External API

**Status**: Draft  
**Author**: Ardonos (with Victor)  
**Created**: 2026-01-25  
**Last Updated**: 2026-01-25  
**Issue**: TBD (Linear)

---

## Executive Summary

Add a public REST API to Dequeue enabling third-party integrations and AI assistants (like Ardonos) to interact with a user's arcs, stacks, tasks, and reminders programmatically. The API exposes a clean, resource-oriented interface while the backend remains event-sourced internally.

**Key Decisions:**
- **API style**: RESTful resource-oriented (not event-sourced externally)
- **Auth**: API keys with scopes (stored in stacks-sync with `app_id`)
- **Deployment**: Separate Go service at `api.dequeue.app`
- **Events**: API operations emit events to stacks-sync (same as iOS app)
- **Documentation**: OpenAPI 3.0 spec with Stoplight for interactive docs
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
- Exposes core Dequeue operations (CRUD for arcs, stacks, tasks, reminders, tags)
- Uses API keys for authentication (tied to user accounts)
- Translates REST operations into internal events
- Returns data in standard JSON format
- Provides auto-generated interactive docs via OpenAPI/Stoplight
- Supports webhooks for real-time notifications (Phase 2)

### 1.3 Goals

- Enable AI assistants to fully manage a user's Dequeue data
- Provide a developer-friendly REST interface with excellent documentation
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
5. **As an AI assistant**, I want to list a user's arcs and stacks, so I can help them organize.
6. **As an AI assistant**, I want to add tasks to a specific stack, so I can help capture work.
7. **As an AI assistant**, I want to mark tasks complete, so I can help track progress.
8. **As an AI assistant**, I want to add reminders to stacks, so I can help with time management.
9. **As a user**, I want to see which integrations accessed my data, so I have visibility.

### 2.2 Ardonos-Specific Stories

1. **As Ardonos**, I want to query Victor's active arcs to understand his strategic priorities.
2. **As Ardonos**, I want to query stacks within an arc to see related work.
3. **As Ardonos**, I want to add tasks with notes/context from our conversations.
4. **As Ardonos**, I want to move tasks between stacks based on Victor's instructions.
5. **As Ardonos**, I want to complete tasks when Victor tells me something is done.
6. **As Ardonos**, I want to create new stacks for emerging projects.
7. **As Ardonos**, I want to add reminders to stacks so Victor doesn't forget things.

---

## 3. API Design

### 3.1 Design Principles

1. **Resource-oriented**: `/arcs`, `/stacks`, `/stacks/{id}/tasks` — not event-based
2. **RESTful verbs**: GET, POST, PUT, PATCH, DELETE
3. **JSON everywhere**: Request and response bodies
4. **Consistent errors**: Standard error format with codes
5. **Idempotent where possible**: PUT/DELETE are idempotent
6. **Pagination**: Cursor-based for lists
7. **Filtering**: Query params for common filters
8. **OpenAPI first**: Spec drives implementation and docs

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
- **Keys stored in stacks-sync database** with `app_id` for multi-app support

#### OAuth 2.0 (v2 — Future)

For third-party apps that need to act on behalf of users:
- Authorization code flow
- Scopes: `arcs:read`, `stacks:read`, `stacks:write`, `tasks:read`, `tasks:write`, `reminders:write`
- Refresh tokens for long-lived access

### 3.5 Endpoints

#### Arcs

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/arcs` | List all arcs |
| POST | `/arcs` | Create an arc |
| GET | `/arcs/{id}` | Get an arc (includes stacks summary) |
| PATCH | `/arcs/{id}` | Update an arc |
| DELETE | `/arcs/{id}` | Archive/delete an arc |
| GET | `/arcs/{id}/stacks` | List stacks in an arc |

#### Stacks

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/stacks` | List all stacks |
| POST | `/stacks` | Create a stack |
| GET | `/stacks/{id}` | Get a stack |
| PATCH | `/stacks/{id}` | Update a stack |
| DELETE | `/stacks/{id}` | Archive/delete a stack |
| POST | `/stacks/{id}/assign-arc` | Assign stack to an arc |

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

#### Reminders

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/stacks/{stackId}/reminders` | List reminders for a stack |
| POST | `/stacks/{stackId}/reminders` | Add a reminder to a stack |
| GET | `/reminders/{id}` | Get a reminder |
| PATCH | `/reminders/{id}` | Update a reminder |
| DELETE | `/reminders/{id}` | Delete a reminder |
| GET | `/arcs/{arcId}/reminders` | List reminders for an arc |
| POST | `/arcs/{arcId}/reminders` | Add a reminder to an arc |

#### Tags

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/tags` | List all tags |
| POST | `/tags` | Create a tag |
| PATCH | `/tags/{id}` | Update a tag |
| DELETE | `/tags/{id}` | Delete a tag |

#### User & API Keys

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

#### Add a Reminder to a Stack

```http
POST /v1/stacks/stk_abc123/reminders
Authorization: Bearer dq_live_xxxx
Content-Type: application/json

{
  "triggerAt": "2026-01-26T09:00:00Z",
  "note": "Follow up on budget review"
}
```

Response:
```json
{
  "id": "rem_xyz789",
  "parentType": "stack",
  "parentId": "stk_abc123",
  "triggerAt": "2026-01-26T09:00:00Z",
  "note": "Follow up on budget review",
  "status": "pending",
  "createdAt": "2026-01-25T02:00:00Z"
}
```

#### List Arcs with Progress

```http
GET /v1/arcs?status=active
Authorization: Bearer dq_live_xxxx
```

Response:
```json
{
  "data": [
    {
      "id": "arc_001",
      "title": "Q1 OEM Strategy",
      "description": "Drive OEM partnerships for conference",
      "status": "active",
      "colorHex": "#4A90D9",
      "stackCount": 3,
      "completedStackCount": 1,
      "createdAt": "2026-01-10T10:00:00Z",
      "updatedAt": "2026-01-24T15:30:00Z"
    }
  ],
  "pagination": {
    "cursor": "eyJpZCI6ImFyY18wMDEifQ",
    "hasMore": false
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

### 4.1 Service Architecture

The API is a **separate Go service** (`dequeue-api`) that:
- Serves REST endpoints at `api.dequeue.app`
- Validates API keys against stacks-sync database
- Emits events to stacks-sync for mutations
- Queries projection tables for reads
- Maintains separation from the generic stacks-sync service

```
┌─────────────────────────────────────────────────────────────┐
│                        Clients                               │
│  (Ardonos, Zapier, iOS App Settings)                        │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│              dequeue-api (Go)                                │
│              api.dequeue.app/v1                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  REST       │  │  Auth       │  │  Event              │  │
│  │  Handlers   │  │  Middleware │  │  Emitter            │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────┬──────────────────────────┬────────────────┘
                  │                          │
                  │ (read API keys,          │ (push events,
                  │  read projections)       │  notify via WS)
                  ▼                          ▼
┌─────────────────────────────────────────────────────────────┐
│              stacks-sync (Go)                                │
│              sync-service.fly.dev                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Events     │  │  API Keys   │  │  WebSocket          │  │
│  │  Table      │  │  Table      │  │  Notifier           │  │
│  │  (app_id)   │  │  (app_id)   │  │                     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│              PostgreSQL                                      │
│  events, api_keys, apps (all with app_id)                   │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Why Separate Service?

1. **Separation of concerns**: stacks-sync is a generic multi-app event relay; Dequeue API is app-specific business logic
2. **Independent deployment**: API can be updated without touching sync infrastructure
3. **Different scaling needs**: API may need different resources than sync
4. **Cleaner codebase**: No mixing of generic sync code with Dequeue-specific endpoints

### 4.3 API Key Storage (in stacks-sync)

API keys are stored in stacks-sync's database, following its multi-tenant pattern:

```sql
CREATE TABLE api_keys (
    id TEXT PRIMARY KEY,
    app_id TEXT NOT NULL REFERENCES apps(id),  -- e.g., 'dequeue'
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,                         -- "Ardonos", "Zapier"
    key_hash TEXT NOT NULL,                     -- bcrypt hash of key
    key_prefix TEXT NOT NULL,                   -- "dq_live_abc" for display
    scopes TEXT[] NOT NULL,                     -- ['read', 'write']
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ
);

CREATE INDEX idx_api_keys_app_user ON api_keys(app_id, user_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_api_keys_prefix ON api_keys(key_prefix);
```

Key format: `dq_live_` + 32 random alphanumeric chars
Only the hash is stored; full key shown once on creation.

### 4.4 Event Flow

When API receives a mutation request:

1. Validate API key → get `user_id`
2. Validate request payload
3. Generate event(s) with proper structure
4. POST event to stacks-sync: `POST /apps/dequeue/sync/push`
5. Query projection tables for response data
6. Return response to client

The API uses a service account or internal auth to push events to stacks-sync on behalf of the user.

### 4.5 Clerk Integration

Clerk handles user authentication for the iOS app. For API keys:

1. **Key creation**: User authenticated via Clerk in app → API call creates key in stacks-sync
2. **Key validation**: dequeue-api queries stacks-sync for key hash → gets `user_id`
3. **No Clerk on API requests**: API keys bypass Clerk entirely (simpler, faster)

### 4.6 Scopes

| Scope | Permissions |
|-------|-------------|
| `read` | GET on all endpoints |
| `write` | POST, PATCH, DELETE on arcs/stacks/tasks/reminders/tags |
| `admin` | Manage API keys, account settings |

Default key gets `read` + `write`. `admin` must be explicitly granted.

---

## 5. API Documentation (OpenAPI + Stoplight)

### 5.1 OpenAPI Specification

The API is defined using **OpenAPI 3.0** specification. The spec file (`openapi.yaml`) is the source of truth for:
- Endpoint definitions
- Request/response schemas
- Authentication requirements
- Error formats

```yaml
openapi: 3.0.3
info:
  title: Dequeue API
  version: 1.0.0
  description: |
    REST API for managing Dequeue arcs, stacks, tasks, and reminders.
    
    ## Authentication
    All endpoints require an API key passed in the Authorization header:
    ```
    Authorization: Bearer dq_live_xxxxxxxxxxxxxxxxxxxx
    ```
servers:
  - url: https://api.dequeue.app/v1
    description: Production
  - url: https://api-staging.dequeue.app/v1
    description: Staging
security:
  - ApiKeyAuth: []
components:
  securitySchemes:
    ApiKeyAuth:
      type: http
      scheme: bearer
# ... paths, schemas, etc.
```

### 5.2 Stoplight Integration

Use **Stoplight** for interactive API documentation:

1. **Host OpenAPI spec** in the dequeue-api repo
2. **Connect Stoplight** to the repo (auto-sync on push)
3. **Publish docs** at `docs.dequeue.app` or `dequeue.stoplight.io`

Stoplight provides:
- Interactive "Try It" functionality
- Auto-generated code samples (curl, JS, Python, etc.)
- Schema validation
- Mock server for testing
- Versioning support

### 5.3 Development Workflow

1. **Spec-first**: Define/update `openapi.yaml` before implementing
2. **Generate types**: Use `oapi-codegen` (Go) to generate request/response types
3. **Validate**: CI checks that implementation matches spec
4. **Publish**: Stoplight auto-updates docs on merge to main

---

## 6. Implementation Phases

### Phase 1: Core API + API Keys (MVP)

**New Service (dequeue-api):**
- Set up Go project with standard structure
- OpenAPI spec for Phase 1 endpoints
- Implement auth middleware (validate keys via stacks-sync)
- Add `/arcs` CRUD endpoints
- Add `/stacks` CRUD endpoints  
- Add `/stacks/{id}/tasks` CRUD endpoints
- Add `/tasks/{id}/complete`, `/move` actions
- Add `/stacks/{id}/reminders` CRUD endpoints
- Emit events to stacks-sync for all mutations
- Basic rate limiting (in-memory)
- Deploy to Fly.io at `api.dequeue.app`
- Set up Stoplight with OpenAPI spec

**stacks-sync Updates:**
- Add `api_keys` table with `app_id`
- Add endpoint to validate API key (internal)
- Add endpoint to create/list/revoke keys

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
- Add filtering: `GET /stacks?arcId=arc_001`
- Add sorting: `?sort=dueDate&order=asc`
- Add search: `?q=budget`
- Improve pagination
- Update OpenAPI spec

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

- Public docs at `docs.dequeue.app`
- Interactive API explorer (Stoplight)
- Rate limit dashboard
- Webhook logs

---

## 7. Security Considerations

### 7.1 API Key Security

- Keys generated with cryptographically secure random bytes
- Only bcrypt hash stored in database
- Full key shown exactly once on creation
- Keys can be scoped to limit damage if leaked
- Keys expire (optional) or can be revoked
- Rate limiting prevents brute force

### 7.2 Data Access

- API keys tied to single user; cannot access other users' data
- All queries filter by `user_id` from validated key
- No admin API for cross-user access
- Keys scoped to `app_id = 'dequeue'`

### 7.3 Transport

- HTTPS only (redirect HTTP)
- TLS 1.2+ required

### 7.4 Audit Logging

- Log all API requests with key prefix (not full key)
- Track `last_used_at` per key
- Future: full audit trail for compliance

---

## 8. Open Questions

| # | Question | Options | Notes |
|---|----------|---------|-------|
| 1 | API key prefix format | `dq_live_` vs `dequeue_` vs `dk_` | Shorter is nicer, but clarity matters |
| 2 | Rate limit storage | In-memory vs Redis | Redis if multi-instance, memory for v1 |
| 3 | Soft vs hard delete | Soft delete (archived) vs permanent | Match app behavior |
| 4 | Event attribution | Mark events as "via API" | Useful for debugging sync issues |
| 5 | Bulk operations | `/tasks/bulk` for batch create | Defer to v2 unless needed |

---

## 9. Success Metrics

- Ardonos can create a task via API
- Ardonos can add a reminder to a stack via API
- Ardonos can list Victor's arcs and stacks
- Task created via API syncs to iOS app within 5 seconds
- API key creation works from iOS settings
- Interactive docs available at Stoplight
- 99.9% API uptime
- P95 latency < 200ms for read operations

---

## 10. Dependencies

- stacks-sync backend (event storage, API key storage, WebSocket notifications)
- Fly.io for deployment
- Stoplight account for docs
- iOS app settings infrastructure
- Secure storage for Ardonos API key (Clawdbot secrets)

---

## 11. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| API key leaked | High | Scopes limit damage; easy revocation; audit logs |
| Rate limiting bypassed | Medium | Per-key + per-IP limits; abuse detection |
| Event sync conflicts | Medium | Same conflict resolution as app (LWW) |
| Scope creep | Medium | Strict v1 scope; defer OAuth/webhooks |
| Performance under load | Medium | Rate limits; caching; horizontal scaling |
| Two services to maintain | Medium | Clear boundaries; shared DB simplifies |

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
# List Victor's active arcs
curl -H "Authorization: Bearer $DEQUEUE_API_KEY" \
  https://api.dequeue.app/v1/arcs?status=active

# List stacks in an arc
curl -H "Authorization: Bearer $DEQUEUE_API_KEY" \
  https://api.dequeue.app/v1/arcs/arc_001/stacks

# Create a task in a stack
curl -X POST \
  -H "Authorization: Bearer $DEQUEUE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"title": "Call dentist to reschedule", "notes": "Victor mentioned this at 2pm"}' \
  https://api.dequeue.app/v1/stacks/stk_inbox/tasks

# Add a reminder to a stack
curl -X POST \
  -H "Authorization: Bearer $DEQUEUE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"triggerAt": "2026-01-26T09:00:00Z", "note": "Follow up on dentist"}' \
  https://api.dequeue.app/v1/stacks/stk_inbox/reminders
```

A Clawdbot skill wraps these calls:

```markdown
## Dequeue Skill

Commands:
- `dequeue list arcs` → GET /arcs
- `dequeue list stacks [arc]` → GET /arcs/{id}/stacks or GET /stacks
- `dequeue list tasks [stack]` → GET /stacks/{id}/tasks
- `dequeue add task [title] to [stack]` → POST /stacks/{id}/tasks
- `dequeue complete [task]` → POST /tasks/{id}/complete
- `dequeue remind [stack] at [time]` → POST /stacks/{id}/reminders
```

---

## Appendix C: Comparison with Similar APIs

| App | Auth | Style | Docs |
|-----|------|-------|------|
| Todoist | API keys + OAuth | REST | Custom |
| Things | None (no API) | — | — |
| Linear | API keys + OAuth | GraphQL | GraphQL Playground |
| Notion | API keys + OAuth | REST | Custom + Postman |
| Asana | OAuth + PAT | REST | Custom |

Dequeue should follow Todoist/Notion patterns with modern docs tooling (Stoplight/OpenAPI).

---

## Appendix D: Project Structure (dequeue-api)

```
dequeue-api/
├── cmd/
│   └── server/
│       └── main.go
├── internal/
│   ├── api/
│   │   ├── arcs.go
│   │   ├── stacks.go
│   │   ├── tasks.go
│   │   ├── reminders.go
│   │   ├── tags.go
│   │   └── users.go
│   ├── auth/
│   │   └── middleware.go
│   ├── events/
│   │   └── emitter.go
│   └── db/
│       └── queries.go
├── openapi/
│   └── openapi.yaml
├── Dockerfile
├── fly.toml
├── go.mod
├── go.sum
└── README.md
```
