# Dequeue Roadmap & Ideas

This document captures feature ideas that are not yet fully specified but worth preserving for future development. Each idea may eventually become a full PRD when ready for implementation.

---

## 1. External System Integrations (Link & Sync)

### Overview
Connect Dequeue to external issue trackers and project management systems, starting with Linear (our own tool), then expanding to Jira, Asana, GitHub Issues, and others.

### Rationale: Why This Matters

Dequeue is a **personal task manager**—not a team-based issue tracking system. However, much of what you personally need to track and work on lives in remote systems. A developer might be working on a Jira ticket. A consultant might have tasks in multiple clients' Asana boards. The reality is that your work is fragmented across systems you don't control.

**The core problem**: Most personal todo apps are completely disconnected from these external systems. This forces you into bad options:
- Track everything in the team system (cluttered, inappropriate for personal micro-tasks)
- Use two separate systems and constantly context-switch between "what's in Jira" and "what's in my personal list"
- Give up on personal task tracking entirely

**The Dequeue approach**: Explicit linking with optional sync.

When you're working on a Jira ticket, you create a Stack in Dequeue and *link* it to that remote issue. Now you can:
- **Break it down your way**: Create as many micro-tasks as you need without polluting the team's issue tracker. Sometimes the truly atomic units of work are too granular for a shared system, but perfect for personal tracking.
- **Work in one place**: Your personal items and your linked work items all live in Dequeue. "What am I doing now?" and "What did I do yesterday?" have one answer, not two.
- **Complete in sync**: When you finish, optionally mark the remote issue as done too. Best of both worlds.
- **Connect multiple systems**: Working for multiple clients with different tools? Link them all. Your personal task manager becomes the unified view across everything.
- **Stay lightweight**: You explicitly choose what to link. We don't automatically sync every issue assigned to you in Jira—that could be a mess. (Though power users can optionally enable auto-sync for assigned issues if they want.)

This is a novel approach we haven't seen in other personal task management software. The insight is that personal productivity tools and team collaboration tools serve different purposes, but they don't have to be islands. Dequeue bridges them while respecting that *you* are the one who decides what enters your personal system.

### Core Concept
- Users can connect **multiple accounts** from various systems (e.g., two Linear workspaces, one Jira instance)
- When creating a Stack or Task, optionally **link** it to a remote issue
- Two modes of connection:
  - **Link Only**: Stores a reference to the foreign issue; no automatic actions
  - **Link + Sync**: Bi-directional synchronization of state changes

### Sync Behavior (when enabled)
| Local Action | Remote Effect |
|--------------|---------------|
| Complete Stack/Task | Mark remote issue as done/closed |
| Reopen Stack/Task | Reopen remote issue |
| (TBD) Update description | Update remote description |
| (TBD) Add comment | Add comment to remote issue |

| Remote Action | Local Effect |
|---------------|--------------|
| Close issue in Linear | Mark linked Stack/Task as completed |
| Reopen issue | Reopen linked Stack/Task |
| (TBD) Update description | Update local description |
| (TBD) Add comment | Surface in local activity/comments |

### Open Questions
- **Sync granularity**: What fields sync? Description, comments, labels/tags, assignees?
- **Conflict resolution**: What happens if both sides change simultaneously?
- **Directionality**: Should some fields be one-way only (e.g., comments sync TO Linear but not FROM)?
- **Filtering**: When linking, how do we present available issues? Search? Recent? By project?

### Technical Considerations

> ⚠️ **This introduces a new architectural pattern for Dequeue.**

Currently, the backend (`stacks-sync`) is mostly a passive event store and sync relay. This feature requires the backend to become an **active participant**:

1. **OAuth & Credential Storage**
   - Cannot store OAuth tokens on-device securely for server-to-server communication
   - Backend must handle OAuth flows for Linear, Jira, etc.
   - Secure credential storage required (encrypted at rest)

2. **Backend-Originated Events**
   - When Linear marks an issue as done, the **backend** detects this (via webhook or polling)
   - Backend then creates and publishes `stack.completed` or `task.completed` events
   - These events propagate to all user devices via existing sync mechanism
   - First time the backend is the **source** of domain events, not just a relay

3. **Webhook Infrastructure**
   - Need to receive webhooks from Linear, Jira, etc.
   - Handle webhook verification, rate limiting, retry logic
   - Map external events to internal domain events

4. **Polling Fallback**
   - Some systems may not support webhooks reliably
   - Need periodic polling to catch missed updates
   - Must handle rate limits gracefully

### Architectural Decision: Separate Service vs. Monolith

A key decision to make early: should integration/sync capabilities live in `stacks-sync` or in a separate service?

**Option A: Extend stacks-sync**
| Pros | Cons |
|------|------|
| Single deployment, simpler ops | Mixes concerns (event relay vs. active integration) |
| Direct access to event store | Harder to scale independently |
| No inter-service communication needed | OAuth/webhook complexity pollutes a simple codebase |
| Faster initial development | Risk of monolith growing unwieldy |

**Option B: Separate integrations service (e.g., `dequeue-integrations`)**
| Pros | Cons |
|------|------|
| Clean separation of concerns | Additional infrastructure to manage |
| Can scale independently (webhooks are bursty) | Inter-service communication complexity |
| Isolates OAuth/credential management | Need to define service API contract |
| Easier to add new integrations without touching core | More moving parts in production |
| Can be developed/deployed independently | Latency for cross-service calls |

**Hybrid Approach?**
- Keep `stacks-sync` as the event backbone
- New service handles OAuth, webhooks, and external API calls
- Integrations service publishes events TO `stacks-sync` (which then propagates to devices)
- Clear boundary: `stacks-sync` never talks to external systems directly

**Recommendation**: Lean toward **separate service** given:
- OAuth and credential storage is security-sensitive (isolation is good)
- Webhook handling has different scaling characteristics
- Future integrations (email, calendar, Slack) compound the complexity
- Keeps `stacks-sync` simple and focused on its core job

This is a decision to make before Phase 1 begins.

### Implementation Phases (suggested)
1. **Phase 1**: Linear OAuth + Link Only (no sync)
2. **Phase 2**: Basic sync (completed state only)
3. **Phase 3**: Extended sync (descriptions, comments)
4. **Phase 4**: Additional integrations (Jira, Asana, GitHub)

---

## 2. Activity Feed / Daily Accomplishments

### Overview
A scrollable feed showing what the user accomplished, summarized by day (and week), with LLM-generated summaries.

### Core Concept
- **Daily cards**: Each card represents one calendar day
- **LLM summary**: A natural language summary of accomplishments (e.g., "You completed 5 tasks across 2 projects, including finishing the API integration")
- **Drill-down**: Tapping a card reveals a timeline view of all activity that day
- **Weekly rollup**: Every Monday, show a weekly summary card covering the previous week

### Card Content
- Stacks activated and/or completed
- Tasks activated and/or completed
- (Future) Events from linked external systems (Linear issues closed, etc.)
- (Future) Emails sent/replied to (requires email integration)

### Timeline Detail View
When tapping into a daily card:
- Chronological list of events throughout the day
- Each event shows timestamp, type (activated/completed), and the Stack/Task
- Visual distinction between activations and completions
- Ability to tap through to the Stack/Task detail

### Weekly Summary
- Appears on Monday mornings
- Summarizes the entire previous week
- Drill-down shows the daily cards for each day of the week
- Useful for weekly reviews, standups, status updates

### Filtering & Organization
- **Tags/Categories**: Filter by personal vs. work (requires tagging system)
- **By Integration**: Show only Linear activity, or only local Dequeue activity
- **Time Range**: View specific date ranges

### Open Questions
- Where does LLM summarization happen? On-device (privacy) vs. server (capability)?
- How do we handle days with no activity? Skip them? Show "No activity" card?
- Should summaries be cached or regenerated on demand?
- How far back should history go? Infinite scroll or pagination?

### Design Considerations
- Cards should feel lightweight and glanceable
- Summaries should be concise (2-3 sentences max)
- Timeline should support a lot of events without performance issues
- Consider sharing capability (share your weekly summary)

### Future Enhancements
- Email integration (emails sent/received)
- Calendar integration (meetings attended)
- Slack integration (messages sent in key channels)
- Custom integrations via API

---

## 3. LLM Task Delegation

### Overview
Any Task can be "delegated" to an AI assistant that will autonomously work on it and report back with results.

### Core Concept
- Toggle on a Task: "Delegate to AI"
- AI takes the task, performs research/actions, and updates the Stack/Task with results
- User reviews the output and can accept, modify, or request more work

### Example Flow
1. User creates Stack: "Get bed sheets"
2. User creates Task: "Research the best sheets for a California King bed"
3. User enables "Delegate to AI" toggle
4. AI researches options, compares reviews, finds best value
5. AI updates the Stack with:
   - Summary of findings
   - Link to recommended product
   - Maybe a comparison table as an attachment
6. User reviews and either purchases or asks for alternatives

### Delegation Types (potential)
| Type | Description | Example |
|------|-------------|---------|
| Research | Gather information and summarize | "Find best sheets for Cal King" |
| Draft | Create content | "Draft email to landlord about lease renewal" |
| Plan | Break down into subtasks | "Plan birthday party for 20 people" |
| Compare | Evaluate options | "Compare AWS vs GCP for our use case" |

### Open Questions
- How do we scope what the AI can/cannot do?
- How do we handle tasks that require human judgment?
- What's the feedback loop? Can user ask for revisions?
- How do we show progress while AI is working?
- Cost considerations (LLM API calls)?
- Privacy: What data is sent to the LLM?

### Technical Considerations
- Likely needs to run on backend (long-running, needs web access)
- Results stored as attachments or structured data on Stack/Task
- May need to integrate with external APIs (search, shopping, etc.)
- Should support cancellation if user changes mind
- Status updates during execution (not just final result)

### Safety & Trust
- Clear indication that AI is acting autonomously
- Human review before any external actions (purchases, emails, etc.)
- Audit log of what AI did and why
- Easy way to undo or correct AI actions

---

## 4. URL Links on Stacks & Tasks

### Overview
Attach URLs to any Stack or Task, displayed as tappable links that open in the user's browser.

### Core Concept
- Similar to attachments, but specifically for URLs
- Rich preview when possible (title, favicon, maybe thumbnail)
- Tap to open in Safari/default browser
- Multiple links per Stack/Task

### Display
- Show favicon + page title (fetched when link is added)
- Fallback to raw URL if metadata unavailable
- Visual distinction from file attachments

### Adding Links
- Paste URL directly
- Share sheet from Safari ("Add to Dequeue")
- Manual entry with optional custom title

### Metadata to Store
- URL (required)
- Title (auto-fetched or custom)
- Favicon URL
- Description/excerpt (optional, from Open Graph)
- Date added
- Thumbnail (optional, from Open Graph)

### Open Questions
- Do we validate URLs are still accessible?
- Do we cache page content for offline reference?
- How do we handle URL changes (redirects, 404s)?
- Should links have categories/types (documentation, reference, purchase, etc.)?

---

## 5. Attachments & Links Gallery

### Overview
A unified view to browse all attachments and links across the entire app, making it easy to find things you've saved.

### Core Concept
- Reverse chronological feed of all attachments and links
- Quick visual scanning (thumbnails for images, icons for files/links)
- Tap to view/open, with easy navigation to the source Stack/Task

### Views
- **All**: Everything in one feed
- **Attachments Only**: Files, images, documents
- **Links Only**: URLs

### Display
- Thumbnail or icon
- File name or link title
- Source Stack/Task name (tappable)
- Date added

### Functionality
- Search within attachments/links
- Filter by type (images, PDFs, links, etc.)
- Filter by date range
- Sort options (newest, oldest, alphabetical)

### Use Cases
- "Where did I save that PDF?"
- "What was that article I linked last week?"
- "Show me all images I've attached recently"
- Quick access to frequently referenced resources

### Open Questions
- How do we handle large numbers of attachments (performance)?
- Should there be a "favorites" or "pinned" concept?
- Do we show attachments from completed/archived Stacks?
- Should this be a tab, a menu item, or a search feature?

---

## Future Ideas (Parking Lot)

Brief notes on other ideas not yet developed:

- **Email Integration**: Connect email accounts to include sent/received emails in activity feed
- **Calendar Integration**: Show meetings in activity timeline
- **Slack Integration**: Track messages in key channels
- **Templates**: Create Stack/Task templates for recurring workflows
- **Recurring Tasks**: Tasks that automatically recreate on a schedule
- **Team Features**: Share Stacks with others, assign Tasks
- **Analytics Dashboard**: Insights on productivity patterns over time

---

## Contributing to This Document

When adding new ideas:
1. Give it a clear, descriptive title
2. Write an overview explaining the core concept
3. List open questions and things to figure out
4. Note any technical considerations or constraints
5. Don't worry about having all the answers—that's what PRDs are for

When an idea is ready for implementation:
1. Create a full PRD in a separate document
2. Create Linear issues for the work
3. Move the idea to an "Implemented" section or remove it

---

*Last updated: January 2026*
