# Dequeue Roadmap & Ideas

This document captures feature ideas that are not yet fully specified but worth preserving for future development. Each idea may eventually become a full PRD when ready for implementation.

---

## 1. External System Integrations (Link & Sync)

### Overview
Connect Dequeue to external issue trackers and project management systems, starting with Linear (our own tool), then expanding to Jira, Asana, GitHub Issues, and others.

### Rationale: Why This Matters

Dequeue is a **personal task manager**—not a team-based issue tracking system. However, much of what you personally need to track and work on lives in remote systems. A developer might be working on a Jira ticket or a GitHub issue. A consultant might have tasks in multiple clients' Asana boards. The reality is that your work is fragmented across systems you don't control.

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
- Users can connect **multiple accounts** from various systems (e.g., two Linear workspaces, one Jira instance, GitHub repos)
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
- (Future) GitHub activity: commits pushed, PRs opened/merged/reviewed, issues closed
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
- GitHub integration (commits, PRs opened/merged/reviewed, issues closed, code reviews)
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

## 6. Idle Reminders & Active Task Check-ins

### Overview
Allow users to set automated reminders that check in on the currently Active Stack/Task when there's been no movement for a configurable period of time. This helps users stay on top of what they're actually working on, especially when multitasking or switching between tasks frequently.

### Rationale: Why This Matters

The core concept of Dequeue is that you're always working on **one and only one thing**—the Active item. But in reality, people multitask and context-switch constantly throughout the day. You might start on Task A, get pulled into a quick Task B, and forget to update Dequeue. An hour later, your Active item is stale and your time tracking is inaccurate.

**The problem**: Most people don't remember to update their task manager when switching contexts. They get into flow on something new and only realize later that Dequeue still shows them working on something from this morning.

**The solution**: Gentle, configurable reminders that ask "Are you still working on X?" after a period of inactivity. This turns Dequeue from a passive tracker into an active partner in maintaining accurate records of what you're doing.

### Core Concept
- **Idle detection**: If no Stack or Task activation/deactivation occurs for a configurable period (e.g., 20 minutes), trigger a reminder
- **Check-in prompt**: "Are you still working on [Active Stack/Task]?"
- **Quick actions from reminder** (simplified for quick taps):
  - "Still working on it" → dismisses reminder, resets idle timer
  - "Switch tasks" → opens app to task switcher
  - "Pause" → deactivates current Stack, nothing becomes Active
- **Time corrections**: When switching to a new Active item, optionally specify when you actually started it (e.g., "I started this 15 minutes ago"). This creates correction events that adjust time tracking without falsifying the real-time event log.

### Time Corrections (Retroactive Events)
A key insight: users often realize they forgot to switch tasks *after the fact*. The naive solution is to backdate events, but this corrupts the integrity of the real-time event log. Instead, we use a **dual-layer approach**:

1. **Real-time layer**: Events are always recorded when they actually happen. If you click "activate Stack B" at 10:20 AM, that's when the event is timestamped. Period.

2. **Correction layer**: A separate event type (`time_correction`) that says "for time tracking purposes, treat Stack B as having started at 10:05 AM."

**Why this matters**:
- The event log remains a truthful record of user actions
- Sync works cleanly (no out-of-order events to reconcile)
- Analytics/time tracking can compute "effective" durations using corrections
- Users can see both: "You clicked at 10:20, but we're counting from 10:05"
- No one is "lying" to the system

**User flow**:
1. Reminder pops up: "Are you still working on Stack A?"
2. User taps "No, switch to..."
3. User selects Stack B
4. Optional prompt: "When did you actually start working on this?"
5. User enters "15 minutes ago" (or picks from suggestions like "30 min ago", "1 hour ago")
6. System records both the real activation event AND the time correction

### Pausing Work (Zero Active Stacks)
This feature represents a small but meaningful shift from the original model:
- **Previously**: Exactly one Stack was always Active
- **New model**: Zero OR one Stacks can be Active

**"Pause" means the human is pausing**, not the Stack. When you pause work:
- The currently Active Stack is deactivated
- No other Stack is activated
- You (the human) are on a break from all tracked work

This is different from switching to another task—it's saying "I'm not working on anything trackable right now."

**Use cases**:
- Stepping away for lunch
- Bathroom break
- Attending a meeting unrelated to any Stack
- Taking a mental break
- Context switch to something not in Dequeue (personal errand, etc.)

**Resume**: When you come back, you can either:
- Reactivate the Stack you were on before the break
- Activate a different Stack
- Stay in "nothing active" mode if you're not ready to start

### Working Hours Preferences
Reminders should respect when you're actually working:
- **Enable/disable during work hours only**: Only send reminders during configured working hours
- **Configurable work schedule**: Set start and end times (e.g., 9 AM - 6 PM)
- **Day selection**: Choose which days are work days (e.g., Monday-Friday)
- **Time zone aware**: Respect user's local time zone
- **Override options**:
  - "Do not disturb" mode for focus time
  - Quick toggle to pause reminders temporarily

### Manual Work Mode Toggle
In addition to scheduled working hours, users can manually control work mode:
- **Optional feature**: Work mode is opt-in. When enabled, the toggle appears on the home screen (above the Stack list)
- **"I'm starting work"**: Manually activate work mode and enable reminders
  - If a Stack is already Active: prompt "Is this what you're starting with?" with option to confirm or switch
  - If no Stack is Active: prompt to select what you're working on
- **"I'm done for today"**: End work mode, deactivate current Stack, disable reminders until next session
- **Use case**: You may not remember to check the Active issue throughout the day, but you do remember "I'm starting work now!" and "I'm heading out"—those are natural bookends
- **Interaction with schedule**: Manual toggle overrides the scheduled hours
  - Turn on manually before scheduled start time → reminders begin immediately
  - Turn off manually before scheduled end time → reminders stop until next day (or manual restart)
- **Visual indicator**: Show current work mode status in the app (working / not working)

### Reminder Preferences
| Setting | Description | Default |
|---------|-------------|---------|
| Idle threshold | Minutes of inactivity before reminder | 20 min |
| Working hours only | Only remind during work hours | On |
| Work start time | When work hours begin | 9:00 AM |
| Work end time | When work hours end | 6:00 PM |
| Work days | Which days to send reminders | Mon-Fri |
| Auto-start work mode | Automatically enter work mode at start time | On |
| Auto-end work mode | Automatically exit work mode at end time | Off |
| Reminder sound | Audio notification | System default |
| Reminder style | Banner, alert, or silent | Banner |

### Technical Considerations

1. **Idle Detection**
   - Track timestamp of last activation/deactivation event
   - Background timer to check idle state
   - Must work reliably even when app is backgrounded
   - iOS: Use background app refresh and local notifications
   - macOS: More flexibility with background execution
   - **Multi-device sync**: Idle state is automatically synced via the event stream (local + remote events). No separate idle tracking needed per device.
   - **Background refresh required**: If iOS background refresh is disabled for this app, show a warning that reminders may be inaccurate across devices

2. **Local Notifications**
   - Schedule notifications based on idle threshold
   - Reschedule when activity occurs
   - Handle notification actions (quick responses)
   - Respect system Do Not Disturb settings
   - **Privacy**: Notification text may show sensitive task names on lock screen
     - Consider configurable text (generic "Still working?" vs. showing task name)
     - Respect iOS notification preview settings (show when unlocked only)
   - **Time-sensitive notifications**: Allow users to enable this in-app so reminders aren't batched/delayed
   - **Notification permissions**: Request permissions when user first enables reminders (not on first launch)
   - **Focus Mode awareness**: Ideally detect if a Focus Mode is blocking notifications and show a dismissible in-app banner alerting the user (if possible via iOS APIs)

3. **Time Corrections via Retroactive Events**

   **The problem**: User forgot to switch from Stack A to Stack B 20 minutes ago. If we backdate the activation event, we're lying about when the user actually clicked. The event log should reflect real-time actions.

   **The solution**: Keep the real-time event log pristine, but add a separate "correction" or "retroactive" event type that records the user's intended timeline.

   When user says "I started this 15 minutes ago":
   - Write the **actual event**: `stack.activated` at current time (10:20 AM) — this is when they clicked
   - Write a **correction event**: `time_correction` that says "Stack B's effective start time should be 10:05 AM, and Stack A's effective end time should be 10:05 AM"

   **Event log stays honest**:
   ```
   10:00 AM - stack.activated (Stack A)     ← real click
   10:20 AM - stack.activated (Stack B)     ← real click
   10:20 AM - time_correction               ← user's correction
              { corrected_start: Stack B @ 10:05 AM,
                corrected_end: Stack A @ 10:05 AM,
                reason: "user_reported" }
   ```

   **Benefits**:
   - Real-time event log is never falsified
   - Time tracking/analytics can use corrected times for accuracy
   - Audit trail shows both what happened and what user intended
   - Sync doesn't have to deal with out-of-order events
   - User gets accurate time records without "lying" to the system

4. **Active Stack State**
   - Model change: Zero OR one Stacks can be Active (previously always exactly one)
   - No new "Paused" state on Stack entity—Stacks are just Active or not Active
   - "Pausing work" = deactivating current Stack without activating another
   - Track when user enters/exits "nothing active" state for break analytics

5. **Work Mode State**
   - Track whether user is currently "at work" or not
   - Persist work mode state across app launches
   - Handle edge cases: app killed while in work mode, device restart, etc.
   - **Syncs across all devices** (like everything else in Dequeue—this is core to how the app works)
   - Use server settings infrastructure for work mode preferences

### Open Questions
- Should reminders persist if you ignore them, or fade away? (Leaning toward: same reminder repeats at the same interval, no escalation)
- How do we handle overlapping breaks (pause Stack A, start Stack B, pause Stack B)?
- Should there be a "snooze" option that delays the reminder by X minutes?
- Do we track break time separately in analytics/activity feed?
- **Notification privacy**: Should notification text be configurable (generic "Still working?" vs. showing task name)?
- **Time corrections**: How far back should users be allowed to correct? 1 hour? 1 day? Unlimited?
- **Time corrections**: Should we show "raw" vs "corrected" time in the activity feed? Or just use corrected silently?
- **Time corrections**: Can users edit/delete corrections after the fact?
- **Time corrections**: Should we auto-suggest correction times based on patterns? ("You usually switch around 10 AM")

### Resolved Questions
- **Work mode toggle location**: Home screen, above the Stack list (when feature is enabled)
- **Starting work mode prompt**: Yes—if a Stack is already Active, ask "Is this what you're starting with?"; if not, prompt to select one
- **Reminder escalation**: No escalation. Same reminder repeats at the configured interval.
- **Focus modes**: iOS handles this at the OS level. We just need to support time-sensitive notifications (user opt-in) and ideally detect/warn if Focus Mode is blocking notifications.
- **Work mode sync**: Yes, syncs across all devices (core to how the app works)

### Implementation Phases (suggested)
1. **Phase 1**: Basic idle reminders with configurable threshold
2. **Phase 2**: Working hours schedule preferences
3. **Phase 3**: Manual work mode toggle (start/end work day)
4. **Phase 4**: Pause work (zero active stacks support)
5. **Phase 5**: Time corrections via retroactive events
6. **Phase 6**: Break tracking and analytics

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
