# PRD: Activity Feed / Daily Accomplishments

**Status**: Draft
**Author**: Claude (with Victor)
**Created**: 2026-01-18
**Last Updated**: 2026-01-18
**Issue**: TBD (Linear)
**iOS Requirements**: iOS 17.0+ (MVP with templates), iOS 18.4+ (on-device LLM)

---

## Executive Summary

A scrollable feed showing what the user accomplished, summarized by day and week, with LLM-generated natural language summaries. The Activity Feed transforms Dequeue from a pure task manager into a personal productivity journal, answering "What did I do?" as effectively as it answers "What should I do next?"

**Key Decisions:**
- **Daily cards**: Each calendar day is represented as a card with summary and drill-down capability
- **Weekly rollups**: Monday mornings show a weekly summary card covering the previous week
- **LLM summaries**: Natural language summaries generated on-device when possible, server-side as fallback
- **Progressive disclosure**: Glanceable cards → tap for timeline detail → tap for entity detail
- **Filtering**: By tags, integration source, and time range
- **History depth**: Infinite scroll with lazy loading; no arbitrary cutoff

---

## 1. Overview

### 1.1 Problem Statement

Users accomplish things every day but have no easy way to reflect on what they've done. The current Dequeue experience is purely forward-looking—focused on "what's next" without visibility into "what I've accomplished." This creates several problems:

1. **No sense of progress**: Users can't easily see their productivity patterns or feel the satisfaction of completed work.

2. **Standup amnesia**: When asked "What did you do yesterday?" in team meetings, users struggle to recall their accomplishments.

3. **Status update friction**: Writing weekly status reports or updating stakeholders requires manually reconstructing what was done.

4. **Fragmented activity**: Work spans multiple systems (Linear, GitHub, email, Dequeue), making it impossible to see a unified view of productivity.

5. **Lost context**: Completed stacks and tasks disappear into a "Completed" tab, losing the temporal context of when they were done.

### 1.2 Proposed Solution

Implement an Activity Feed that provides a chronological, day-by-day view of accomplishments with these core capabilities:

1. **Daily Summary Cards**: Glanceable cards showing what was accomplished each day, with LLM-generated natural language summaries (e.g., "You completed 5 tasks across 2 projects, including finishing the API integration").

2. **Timeline Detail View**: Drill down into any day to see a chronological list of all events with timestamps.

3. **Weekly Rollups**: Monday mornings surface a weekly summary card covering the previous week, perfect for weekly reviews and status updates.

4. **Cross-System Integration**: Future-ready architecture to incorporate activity from linked external systems (GitHub, Linear, email, calendar).

5. **Smart Filtering**: Filter by tags, integration source, or time range to focus on specific areas of work.

### 1.3 Goals

- Enable users to quickly answer "What did I accomplish yesterday/this week?"
- Provide a sense of progress and accomplishment through visual feedback
- Support standup meetings and status updates with easily accessible summaries
- Create infrastructure for future cross-system activity aggregation
- Maintain Dequeue's offline-first, privacy-respecting architecture

### 1.4 Non-Goals

- Real-time activity streaming (batch updates are sufficient)
- Gamification (streaks, badges, achievements)
- Social sharing beyond personal copy/export
- Predictive analytics ("You usually complete X tasks on Fridays")
- Calendar view of activity (timeline-based, not calendar-based)
- Editing or modifying historical activity (read-only view)

---

## 2. User Stories

### 2.1 Primary User Stories

1. **As a user**, I want to see a summary of what I accomplished yesterday so I can quickly recall my progress in standup meetings.

2. **As a user**, I want natural language summaries of my accomplishments so I don't have to mentally aggregate a list of events.

3. **As a user**, I want to drill down into any day to see the exact timeline of what I did and when.

4. **As a user**, I want a weekly summary on Monday mornings so I can review my previous week and plan the current one.

5. **As a user**, I want to filter my activity by project/tag so I can see work related to specific areas.

6. **As a user**, I want to scroll back through my activity history to find when I worked on something specific.

7. **As a user**, I want to tap on an activity item to navigate to that stack or task for more context.

8. **As a user**, I want my activity data to work offline so I can review it without internet connection.

9. **As a user**, I want to share or copy a daily/weekly summary to paste into status updates or messages.

### 2.2 Secondary User Stories

10. **As a user**, I want to see my GitHub activity (commits, PRs) alongside my Dequeue activity (future integration).

11. **As a user**, I want to see linked Linear issues that were closed alongside my Dequeue completions (future integration).

12. **As a user**, I want privacy—my activity summaries should be processed locally when possible.

### 2.3 Edge Cases

- User has no activity for a day → Skip that day in the feed (don't show empty cards)
- User has activity spanning midnight → Group by calendar day in user's local timezone
- User views activity across timezone change → Show in user's current timezone with adjustment note if significant
- User deletes a stack/task that was in activity → Show "deleted item" placeholder, don't remove from history
- LLM summarization fails → Fall back to simple structured summary ("Completed 3 tasks, activated 2 stacks")
- User opens app for first time → Show friendly empty state with explanation

---

## 3. Technical Design

### 3.1 Data Model

The Activity Feed is built on top of the existing `Event` model. No new data models are required for the core MVP, but we add supporting structures for summaries and caching.

#### 3.1.1 Existing Event Model (Already Implemented)

```swift
@Model
final class Event {
    @Attribute(.unique) var id: String
    var type: String           // e.g., "stack.completed", "task.activated"
    var entityId: String       // The stack or task ID
    var timestamp: Date
    var deviceId: String
    var payload: Data?         // JSON-encoded state snapshot
    var syncState: SyncState
    // ...
}
```

#### 3.1.2 New: Daily Summary Cache (Local Only, Not Synced)

**Design Decision**: ActivitySummary is device-local and regenerated on each device rather than synced. See "Summary Sync Strategy" in Key Technical Decisions below for rationale.

```swift
@Model
final class ActivitySummary {
    @Attribute(.unique) var id: String    // Format: "YYYY-MM-DD" or "YYYY-Www" for weekly
    var summaryType: SummaryType          // .daily or .weekly
    var date: Date                        // Start of day/week
    var summaryText: String               // LLM-generated summary
    var eventCount: Int                   // Number of events included
    var completedCount: Int               // Stacks + tasks completed
    var activatedCount: Int               // Stacks + tasks activated
    var generatedAt: Date                 // When summary was generated
    var modelVersion: String              // LLM model version for cache invalidation
    var isStale: Bool                     // True if new events added after generation

    // NOT included: No relationship to Event entities (cache is ephemeral)
    // NOT included: No sync fields (local cache only, not synced)
}

enum SummaryType: String, Codable {
    case daily
    case weekly
}
```

#### 3.1.3 Event Types for Activity Feed

**Note**: This table is synchronized with `EventType` enum in `Dequeue/Models/Enums.swift`.

| Event Type | Activity Display | Include in Summary |
|------------|------------------|-------------------|
| `stack.completed` | "✓ Completed: [Stack Name]" | Yes |
| `stack.closed` | "🔒 Closed: [Stack Name]" | Yes (distinct from completed) |
| `stack.activated` | "▶ Started: [Stack Name]" | Yes |
| `stack.deactivated` | "⏸ Paused: [Stack Name]" | Optional (useful when switching stacks) |
| `stack.discarded` | — | No (draft stacks, not meaningful) |
| `task.completed` | "✓ Completed task: [Task Title]" | Yes |
| `task.closed` | "🔒 Closed task: [Task Title]" | Yes (distinct from completed) |
| `task.activated` | "▶ Started task: [Task Title]" | Yes |
| `stack.created` | "➕ Created: [Stack Name]" | Optional |
| `task.created` | — | No (too noisy) |
| `attachment.added` | "📎 Added attachment to [Entity]" | Optional |
| `attachment.removed` | "🗑 Removed attachment from [Entity]" | Optional |

**Distinctions**:
- **Completed vs. Closed**: "Completed" means finished with all tasks done; "Closed" means archived without necessarily completing all tasks
- **Stack.deactivated**: Shows when switching between stacks (relevant for "exactly one active stack" model per PROJECT.md)

### 3.2 Activity Feed Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      ActivityFeedView                        │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                  Daily Card (Today)                      │ │
│  │  "You completed 3 tasks across 2 projects..."           │ │
│  │  [Tap to expand timeline]                               │ │
│  └─────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                Daily Card (Yesterday)                    │ │
│  │  "Productive day! You finished the API integration..."  │ │
│  │  [Tap to expand timeline]                               │ │
│  └─────────────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │            Weekly Summary Card (Monday)                  │ │
│  │  "Last week: 12 tasks completed, 4 stacks finished..."  │ │
│  │  [Tap to see daily breakdown]                           │ │
│  └─────────────────────────────────────────────────────────┘ │
│  ...                                                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ (Tap)
┌─────────────────────────────────────────────────────────────┐
│                 DayTimelineDetailView                        │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  2:30 PM  ✓ Completed: API Integration                  │ │
│  │  1:15 PM  ▶ Started: Documentation                      │ │
│  │  11:00 AM ✓ Completed task: Fix login bug               │ │
│  │  9:30 AM  ▶ Started: API Integration                    │ │
│  │  9:00 AM  ➕ Created: Weekly Planning                   │ │
│  └─────────────────────────────────────────────────────────┘ │
│                              │                               │
│                              ▼ (Tap row)                     │
│                    Navigate to Stack/Task                    │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 LLM Summary Generation

#### 3.3.1 Summary Strategy

The feature uses a tiered approach to summary generation:

1. **On-Device (Primary)**: Use Apple's Foundation Models framework (iOS 18.4+) for privacy-preserving, offline-capable summarization.

2. **Backend Fallback**: If on-device unavailable or fails, request summary from backend LLM service.

3. **Template Fallback**: If both fail, generate structured template summary: "You completed X tasks across Y stacks, including [top completions]."

#### 3.3.2 On-Device LLM (iOS 18.4+)

**Availability Note**: Apple's Foundation Models framework requires iOS 18.4+, which is in beta as of January 2026. For devices running iOS 17.0-18.3, the implementation will fall back to template-based summaries (Phase 1) or backend LLM (Phase 6).

**Deployment Strategy**:
- **Phase 1-2 (MVP)**: Template-based summaries work on all iOS 17.0+ devices
- **Phase 3**: On-device LLM enabled conditionally for iOS 18.4+ devices
- **Phase 6**: Backend LLM provides enhanced summaries for pre-18.4 devices

```swift
import FoundationModels

actor ActivitySummarizer {
    func generateDailySummary(events: [Event], for date: Date) async throws -> String {
        // Check iOS version availability
        guard #available(iOS 18.4, *) else {
            throw SummaryError.onDeviceLLMUnavailable
        }

        do {
            let model = SystemLanguageModel.default

            let prompt = """
            Summarize this person's productivity for \(date.formatted()):

            Completed:
            \(formatCompletions(events))

            Started:
            \(formatActivations(events))

            Write 2-3 sentences highlighting key accomplishments. Be specific but concise.
            """

            let response = try await model.generate(prompt: prompt)
            return response.text
        } catch {
            // Log error and rethrow for fallback handling
            logger.error("On-device LLM generation failed: \(error)")
            throw error
        }
    }
}

enum SummaryError: Error {
    case onDeviceLLMUnavailable
    case generationFailed
}
```

#### 3.3.3 Backend LLM Endpoint (Fallback)

```
POST /apps/{app_id}/activity/summarize
Request:
{
    "date": "2026-01-17",
    "type": "daily",  // or "weekly"
    "events": [
        { "type": "stack.completed", "name": "API Integration", "timestamp": "..." },
        { "type": "task.completed", "name": "Fix login bug", "timestamp": "..." },
        // ...
    ]
}

Response:
{
    "summary": "You had a productive day! You completed the API Integration project and fixed 3 bugs. Your focus on the authentication system is paying off.",
    "model_version": "gpt-4o-2024-01"
}
```

#### 3.3.4 Summary Caching

- Summaries are cached in `ActivitySummary` model
- Cache key: date + summary type (daily/weekly)
- Invalidation: Mark `isStale = true` when new events arrive for that period
- Regeneration: On next view if stale, regenerate in background
- TTL: None (summaries for past days rarely need regeneration)

### 3.4 Filtering System

#### 3.4.1 Filter Options

```swift
struct ActivityFilter {
    var tags: Set<Tag>?           // Filter to specific tags
    var integrationSources: Set<IntegrationSource>?  // local, linear, github, etc.
    var dateRange: ClosedRange<Date>?  // Custom date range
    var eventTypes: Set<ActivityEventType>?  // completions, activations, etc.
}

enum IntegrationSource: String, CaseIterable {
    case local = "Dequeue"
    case linear = "Linear"
    case github = "GitHub"
    case email = "Email"
    case calendar = "Calendar"
}
```

#### 3.4.2 Filter UI

- Toolbar button opens filter sheet
- Quick pills for common filters: "Work", "Personal", "This Week"
- Active filter indicator in toolbar
- Clear filters button

### 3.5 Offline-First Behavior

1. **Event Storage**: All events stored locally via existing sync system
2. **Summary Cache**: Generated summaries stored in local SwiftData
3. **Offline Summary Generation**: On-device LLM works offline (iOS 18.4+)
4. **Fallback**: Template summaries always available offline
5. **Sync**: No activity-specific sync needed—events sync via existing mechanism

### 3.6 Performance Considerations

#### 3.6.1 Query Optimization

**Note**: Use `EventType` enum values, not raw strings, per CLAUDE.md style guide.

```swift
// Efficient query for daily events
// For MVP (Phase 1), use simpler query and filter in ViewModel:
@Query(
    filter: #Predicate<Event> {
        $0.timestamp >= sevenDaysAgo
    },
    sort: \Event.timestamp,
    order: .reverse
) private var recentEvents: [Event]

// Phase 2+: Add computed property to Event model for filtering
// In Event.swift:
extension Event {
    var isActivityRelevant: Bool {
        guard let eventType else { return false }

        switch eventType {
        case .stackCompleted, .stackClosed, .stackActivated, .stackDeactivated,
             .taskCompleted, .taskClosed, .taskActivated,
             .stackCreated, .attachmentAdded, .attachmentRemoved:
            return true
        default:
            return false
        }
    }
}

// Then in query:
@Query(
    filter: #Predicate<Event> {
        $0.timestamp >= dayStart &&
        $0.timestamp < dayEnd &&
        $0.isActivityRelevant
    },
    sort: \Event.timestamp,
    order: .reverse
) private var dayEvents: [Event]
```

**Performance Considerations**:
- Add index on `Event.timestamp` in SwiftData schema
- Limit initial query to 7-30 days to prevent scanning entire event log
- Use computed property `isActivityRelevant` instead of inline type checks for maintainability

#### 3.6.2 Lazy Loading

- Load 7 days initially
- Fetch more on scroll (pagination)
- Prefetch next batch when approaching end
- Target: <500ms load time for initial view

#### 3.6.3 Summary Generation Timing

- Generate summaries on-demand when card first visible
- Cache aggressively (past summaries don't change)
- Background generation during idle time
- Today's summary regenerates periodically (every hour or on significant events)

---

## 3.7 Key Technical Decisions

### 3.7.1 Summary Sync Strategy: Local-Only Regeneration

**Decision**: ActivitySummary data is NOT synced between devices. Each device regenerates summaries locally from synced Event data.

**Rationale**:

1. **Privacy Alignment**: On-device LLM is the primary summarization method. Syncing summaries would undermine the privacy benefit of local processing.

2. **Conflict Avoidance**: Different devices may generate slightly different summaries due to:
   - Different iOS versions (18.4+ with on-device LLM vs. older with templates)
   - Different LLM model versions over time
   - Timing differences in when summaries are generated

   Last-Write-Wins (LWW) conflict resolution would cause confusing inconsistencies where Device A sees one summary and Device B sees another for the same day.

3. **Source of Truth**: Events are the source of truth (per PROJECT.md event-first architecture). Summaries are derived views that can be regenerated at any time.

4. **Cache Invalidation**: If synced, summary invalidation logic becomes complex:
   - What if Event data changes after summary sync?
   - What if entity names change (stack renamed)?
   - Simpler to treat summaries as ephemeral local cache.

5. **Bandwidth Efficiency**: Summary text is larger than event data. Regenerating locally saves sync bandwidth.

**Implementation**:
- `ActivitySummary` model has NO sync-related fields (no `serverId`, no `updatedAt`)
- Summaries regenerated on-demand when missing or marked stale
- Backend LLM fallback (Phase 6) generates summaries on-demand but does NOT store them centrally

**Trade-off Accepted**: Devices will do duplicate work generating summaries. This is acceptable because:
- Most summaries are generated once and cached indefinitely (past days don't change)
- Only "Today" summary regenerates frequently
- On-device LLM is fast (<3 seconds per summary)

---

## 4. UI/UX Design

### 4.1 Activity Feed Main View

```
┌─────────────────────────────────────────────────────────────┐
│ Activity                                    [Filter] [Share]│
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ TODAY                                          Jan 18   ││
│  │                                                         ││
│  │ You completed 3 tasks across 2 projects, including      ││
│  │ finishing the API integration and making progress on    ││
│  │ the documentation.                                      ││
│  │                                                         ││
│  │ ✓ API Integration                                       ││
│  │ ✓ Fix login bug                                         ││
│  │ ✓ Update README                                         ││
│  │                                              [See all →] ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ YESTERDAY                                      Jan 17   ││
│  │                                                         ││
│  │ Productive day! You completed the user authentication   ││
│  │ feature and started work on the notification system.    ││
│  │                                                         ││
│  │ ✓ User Authentication                                   ││
│  │ ▶ Notification System                                   ││
│  │                                              [See all →] ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ 📅 WEEK OF JAN 6-12                                     ││
│  │                                                         ││
│  │ Great week! You completed 12 tasks and finished 4       ││
│  │ major projects. Highlights include shipping the         ││
│  │ payment integration and completing the design review.   ││
│  │                                                         ││
│  │ 12 tasks completed · 4 projects finished                ││
│  │                                        [See breakdown →]││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  ... (infinite scroll)                                      │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Daily Card Design

#### 4.2.1 Card States

**Full Day Card (with activity)**:
- Header: Day name + date (e.g., "TODAY", "YESTERDAY", "MONDAY, JAN 15")
- LLM Summary: 2-3 sentences
- Completion list: Up to 5 items with icons
- "See all →" link if more than 5 items

**Empty Day**: Skip entirely (no empty cards shown)

**Today (Partial)**: Shows activity so far, summary updates throughout day

#### 4.2.2 Card Visual Design

```
┌──────────────────────────────────────────────────────────┐
│  TODAY                                          Jan 18   │  ← Header
├──────────────────────────────────────────────────────────┤
│                                                          │
│  You completed 3 tasks across 2 projects, including      │  ← LLM Summary
│  finishing the API integration and making progress on    │    (2-3 sentences)
│  the documentation.                                      │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  ✓ API Integration                              2:30 PM  │  ← Top Completions
│  ✓ Fix login bug                               11:00 AM  │    (up to 5)
│  ✓ Update README                                9:15 AM  │
├──────────────────────────────────────────────────────────┤
│  3 completions · 2 activations            [See all →]    │  ← Footer
└──────────────────────────────────────────────────────────┘
```

### 4.3 Timeline Detail View

When user taps a daily card:

```
┌─────────────────────────────────────────────────────────────┐
│ ← Back          Friday, January 17                    Share │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  You had a productive day! You completed the user           │
│  authentication feature and started work on the             │
│  notification system.                                       │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  5:30 PM  ✓ Completed: User Authentication           [→]   │
│           Finished all remaining tasks                      │
│                                                             │
│  3:45 PM  ✓ Completed task: Add OAuth flow           [→]   │
│           Part of: User Authentication                      │
│                                                             │
│  2:00 PM  ▶ Started: Notification System             [→]   │
│           Began work on push notifications                  │
│                                                             │
│  1:30 PM  ✓ Completed task: Fix token refresh        [→]   │
│           Part of: User Authentication                      │
│                                                             │
│  10:00 AM ▶ Started: User Authentication             [→]   │
│           Resumed from yesterday                            │
│                                                             │
│  9:00 AM  ➕ Created: Weekly Planning                [→]   │
│           New stack for the week                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 4.4 Weekly Summary Card

Appears on Monday mornings (or first app open after Monday):

```
┌──────────────────────────────────────────────────────────┐
│  📅 WEEK OF JANUARY 6-12                                 │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  Great week! You completed 12 tasks and finished 4       │
│  major projects. Highlights include shipping the         │
│  payment integration and completing the design review.   │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  📊 12 tasks completed                                   │
│  📦 4 projects finished                                  │
│  ⏱  15.5 hours tracked                                  │
├──────────────────────────────────────────────────────────┤
│  Top projects:                                           │
│  1. Payment Integration (5 tasks)                        │
│  2. User Authentication (3 tasks)                        │
│  3. Documentation (2 tasks)                              │
├──────────────────────────────────────────────────────────┤
│                                        [See daily breakdown →]│
└──────────────────────────────────────────────────────────┘
```

### 4.5 Empty State

For new users or after a break:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│                          📊                                 │
│                                                             │
│                   No Activity Yet                           │
│                                                             │
│         Complete some tasks to see your daily               │
│         accomplishments and progress here.                  │
│                                                             │
│                [Go to Stacks →]                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 4.6 Filter Sheet

```
┌─────────────────────────────────────────────────────────────┐
│                   Filter Activity                     [Done]│
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  TIME RANGE                                                 │
│  ┌─────────┬──────────┬───────────┬──────────────────┐     │
│  │ All Time│ This Week│ This Month│ Custom Range...  │     │
│  └─────────┴──────────┴───────────┴──────────────────┘     │
│                                                             │
│  SOURCES                                                    │
│  ☑ Dequeue tasks                                           │
│  ☐ Linear (not connected)                                  │
│  ☐ GitHub (not connected)                                  │
│                                                             │
│  TAGS                                                       │
│  ┌───────┐ ┌──────────┐ ┌──────┐                          │
│  │ Work  │ │ Personal │ │ Docs │ ...                       │
│  └───────┘ └──────────┘ └──────┘                          │
│                                                             │
│  EVENT TYPES                                                │
│  ☑ Completions                                             │
│  ☑ Activations                                             │
│  ☐ Creations                                               │
│                                                             │
│                     [Clear Filters]                         │
└─────────────────────────────────────────────────────────────┘
```

### 4.7 Share/Export

Users can share daily or weekly summaries:

**Share Options:**
- Copy as text (for Slack, email, status updates)
- Share sheet (standard iOS share)

**Export Format (Text)**:
```
📅 Friday, January 17, 2026

You had a productive day! You completed the user authentication
feature and started work on the notification system.

Completed:
✓ User Authentication
✓ Add OAuth flow
✓ Fix token refresh

Started:
▶ Notification System

---
Generated by Dequeue
```

### 4.8 Platform Considerations

#### iOS/iPadOS
- Standard List with custom card cells
- Pull-to-refresh for today's summary
- Swipe actions for sharing individual cards
- Haptic feedback on card tap

#### macOS
- Same card-based layout
- Hover states on cards
- Keyboard navigation (up/down arrows)
- ⌘C to copy selected day's summary

---

## 5. Decisions Made

| Question | Decision | Rationale |
|----------|----------|-----------|
| Days with no activity | Skip (no empty cards) | Cleaner feed; empty cards add noise |
| Summary generation | On-device primary, backend fallback | Privacy-first; works offline |
| Summary cache invalidation | Mark stale, regenerate on view | Balances freshness with performance |
| History depth | Infinite scroll, no cutoff | Users may need to find old activity |
| Weekly summary timing | Monday mornings | Natural start-of-week review point |
| Share format | Plain text | Universal compatibility |
| Event types in feed | Completions + activations | Most meaningful; creations optional |
| Filter persistence | Session-only | Simple UX; users rarely need persistent filters |
| Template fallback | Always available | Ensures feature works even if LLM fails |

---

## 6. Open Questions

| # | Question | Options | Recommendation |
|---|----------|---------|----------------|
| 1 | Summary tone | Professional vs. casual vs. enthusiastic | Slightly enthusiastic ("Great day!") |
| 2 | Today's summary refresh | Hourly vs. on significant events vs. manual | On significant events + every 2 hours |
| 3 | Activity notifications | Daily summary notification option | Yes, opt-in "Your daily summary is ready" |
| 4 | Widget support | Show yesterday's summary in widget | Yes, small and medium widgets |
| 5 | Calendar view option | Timeline vs. calendar grid view | Timeline primary; calendar future enhancement |
| 6 | Time tracking display | Show duration in cards | Yes, if time tracking data available |

**Resolved Questions** (See Section 3.7 for decisions):
- ~~Cross-device summary sync~~ → **DECIDED**: Local-only regeneration (not synced)

---

## 7. Success Metrics

### 7.1 Engagement Metrics
- **Daily Active Viewers**: % of DAU who view Activity tab
- **Card Tap Rate**: % of cards tapped for detail view
- **Scroll Depth**: Average number of days scrolled back
- **Share Rate**: % of users who share at least one summary

### 7.2 Performance Metrics
- **Initial Load Time**: <500ms for first 7 days
- **Summary Generation**: <3 seconds for LLM summary
- **Scroll Performance**: 60fps while scrolling

### 7.3 Satisfaction Metrics
- **Standup Usefulness**: User survey on standup preparation
- **Summary Quality**: Thumbs up/down on generated summaries
- **Feature Retention**: Users returning to Activity tab over time

---

## 8. Implementation Phases

### Phase 1: MVP - Event Timeline (Crawl)
**Goal**: Basic activity visibility without LLM

**Backend:**
- No backend changes required (uses existing events)

**iOS:**
- Create `ActivityFeedView` with sectioned list by day
- Create `ActivityRowView` for individual events
- Create `ActivityEmptyView` for empty state
- Query `Event` model for relevant types
- Group events by calendar day
- Tap row to navigate to stack/task
- Add Activity tab to main navigation

**No LLM yet**: Show structured list only ("Completed: X", "Started: Y")

### Phase 2: Daily Cards & Template Summaries (Walk)
**Goal**: Card-based UI with template summaries

**iOS:**
- Create `DailyActivityCard` view
- Create `DayTimelineDetailView` for drill-down
- Implement template summary generation (no LLM):
  - "You completed X tasks across Y stacks"
  - "Today: X completions, Y activations"
- Add `ActivitySummary` model for caching
- Add share functionality (copy as text)
- Pull-to-refresh for today

### Phase 3: LLM Summaries - On-Device (Walk)
**Goal**: Natural language summaries via Apple Foundation Models

**iOS:**
- Integrate Apple Foundation Models framework (iOS 18.4+)
- Create `ActivitySummarizer` actor
- Implement prompt engineering for quality summaries
- Cache generated summaries
- Graceful fallback to template if LLM unavailable
- Background summary generation

**Requires**: iOS 18.4+ for Foundation Models

### Phase 4: Weekly Rollups (Walk)
**Goal**: Weekly summary cards on Mondays

**iOS:**
- Generate weekly summaries on Sunday night / Monday morning
- Create `WeeklyActivityCard` view
- Drill-down shows daily cards for the week
- Summary includes: total completions, top projects, time tracked

### Phase 5: Filtering & Polish (Walk)
**Goal**: Filter by tags, sources, time range

**iOS:**
- Create `ActivityFilterView` sheet
- Implement tag filtering
- Implement time range filtering
- Source filtering (future: integration sources)
- Event type filtering
- Clear filters action

### Phase 6: Backend LLM Fallback (Run)
**Goal**: Server-side summary generation for older devices

**Backend:**
- `POST /activity/summarize` endpoint
- LLM integration (OpenAI, Anthropic, or Claude)
- Rate limiting and cost management
- Response caching

**iOS:**
- Fallback to backend if on-device unavailable
- Handle network errors gracefully

### Phase 7: Integration Sources (Run - Future)
**Goal**: Include activity from linked external systems

**Backend:**
- Event normalization from Linear, GitHub, etc.
- Activity aggregation endpoint

**iOS:**
- Display integrated activities in feed
- Filter by source
- Visual distinction for external events

### Phase 8: Widgets & Notifications (Run - Future)
**Goal**: Surface summaries outside the app

**iOS:**
- Small widget: "Yesterday: X completed"
- Medium widget: Today's top accomplishments
- Optional daily summary notification

---

## 9. Dependencies

### 9.1 Required
- Existing `Event` model and sync system
- SwiftUI List and ScrollView
- SwiftData for summary caching

### 9.2 For LLM Features
- Apple Foundation Models framework (iOS 18.4+)
- OR Backend LLM service integration

### 9.3 For Future Integrations
- External System Integrations feature (see ROADMAP Section 1)
- Linear, GitHub OAuth connections

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| LLM summary quality varies | Medium | Template fallback; user feedback mechanism |
| On-device LLM not available on all devices | Medium | Backend fallback; template fallback |
| Large event history impacts performance | Medium | Lazy loading; limit initial query to 30 days |
| Summary generation costs (backend) | Medium | Cache aggressively; rate limit per user |
| Privacy concerns with backend LLM | High | On-device primary; clear disclosure if using backend |
| Users don't discover the feature | Medium | Onboarding tooltip; tab badge for first week |
| Summary doesn't match user's perception | Low | Show raw events; allow feedback |
| Timezone edge cases | Low | Use local timezone; clear date headers |

---

## Appendix A: LLM Prompt Engineering

### A.1 Daily Summary Prompt

```
You are summarizing a person's productivity for a single day. Be encouraging but honest.

Date: {date}

Events:
{formatted_events}

Guidelines:
- Write 2-3 sentences maximum
- Highlight the most significant completions
- Use specific project/task names
- Be concise and direct
- If many completions, focus on the highlights
- If few completions, acknowledge progress on ongoing work
- Don't use generic phrases like "busy day" without specifics

Example output:
"Great progress today! You completed the API Integration project and finished 3 tasks on User Authentication. The bug fixes are really adding up."
```

### A.2 Weekly Summary Prompt

```
You are summarizing a person's productivity for the past week. Be encouraging and highlight patterns.

Week: {week_start} to {week_end}

Daily summaries:
{daily_summaries}

Totals:
- Tasks completed: {task_count}
- Projects finished: {project_count}
- Total time tracked: {time_tracked}

Guidelines:
- Write 3-4 sentences maximum
- Highlight the week's biggest accomplishments
- Note any projects that were completed
- Mention patterns if relevant (e.g., "strong finish to the week")
- Be specific about what was achieved
- Keep tone professional but warm

Example output:
"Excellent week! You shipped the Payment Integration project and made major progress on User Authentication. With 12 tasks completed across 4 projects, you maintained strong momentum throughout the week. The documentation work on Friday sets you up well for next week."
```

---

## Appendix B: Event Payload Decoding

To display meaningful activity information, we decode the event payload:

```swift
struct EventPayload: Codable {
    let state: EntityState?

    struct EntityState: Codable {
        let id: String
        let title: String?
        let name: String?  // Some entities use 'name' instead of 'title'
        let status: String?
        let parentId: String?
        let parentType: String?
    }
}

extension Event {
    var entityName: String {
        guard let payloadData = payload,
              let payload = try? JSONDecoder().decode(EventPayload.self, from: payloadData),
              let state = payload.state else {
            return "Unknown"
        }
        return state.title ?? state.name ?? "Untitled"
    }
}
```

---

## Appendix C: Accessibility

### C.1 VoiceOver Support
- Cards announce: "Today, January 18. 3 tasks completed. [Summary text]"
- Timeline rows announce: "2:30 PM, Completed, API Integration"
- Filter button: "Filter activity, button"

### C.2 Dynamic Type
- Summary text scales with system settings
- Card layout adapts (vertical on larger sizes)
- Minimum tap target 44pt

### C.3 Reduce Motion
- Disable card expand/collapse animations
- Use crossfade instead of slide transitions

---

## Appendix D: Future Enhancements

### D.1 GitHub Integration
- Commits pushed
- PRs opened, merged, reviewed
- Issues closed
- Code review activity

### D.2 Email Integration
- Emails sent
- Emails replied to
- Threading support

### D.3 Calendar Integration
- Meetings attended
- Meeting duration tracking

### D.4 Slack Integration
- Messages in key channels
- Thread participation

### D.5 Custom Integrations
- Webhook API for custom events
- User-defined event types

---

*Last updated: January 2026*
