# PRD: Activity Feed / Daily Accomplishments

**Status**: Draft
**Author**: Claude (with Victor)
**Created**: 2026-01-18
**Last Updated**: 2026-01-18 (v2 - incorporated multi-model feedback)
**Issue**: TBD (Linear)

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

#### 3.1.2 New: Daily Summary Cache (Local Only)

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
}

enum SummaryType: String, Codable {
    case daily
    case weekly
}
```

#### 3.1.3 Event Types for Activity Feed

| Event Type | Activity Display | Include in Summary |
|------------|------------------|-------------------|
| `stack.completed` | "✓ Completed: [Stack Name]" | Yes |
| `stack.activated` | "▶ Started: [Stack Name]" | Yes |
| `stack.deactivated` | — | No (not meaningful) |
| `task.completed` | "✓ Completed task: [Task Title]" | Yes |
| `task.activated` | "▶ Started task: [Task Title]" | Yes |
| `task.deactivated` | — | No (not meaningful) |
| `stack.created` | "➕ Created: [Stack Name]" | Optional |
| `task.created` | — | No (too noisy) |
| `attachment.added` | "📎 Added attachment to [Entity]" | Optional |

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

1. **Template Fallback (Always Available)**: Generate structured template summary: "You completed X tasks across Y stacks, including [top completions]." This ensures the feature works on all devices, offline, with zero dependencies.

2. **On-Device LLM (Primary for Enhanced Summaries)**: Use Apple's Foundation Models framework (iOS 26+) for privacy-preserving, offline-capable natural language summarization.

3. **Backend LLM (Cloud Fallback)**: If on-device unavailable or for weekly rollups exceeding on-device limits, request summary from backend LLM service (Claude).

#### 3.3.2 On-Device LLM Constraints (iOS 26+)

**Critical Limitations:**
| Constraint | Value | Impact |
|------------|-------|--------|
| Context Window | **4,096 tokens** (input + output combined) | Limits daily summaries to ~50-60 events |
| Model Size | 3 billion parameters | Less reasoning power than cloud models |
| Device Support | Apple Intelligence-compatible only | Excludes older devices (iPhone 14 and earlier) |
| iOS Version | iOS 26+ | Requires latest OS |

**Token Budget for Daily Summaries:**
- System prompt: ~200 tokens
- Event data (50 events): ~2,000-2,500 tokens
- Output summary: ~200-300 tokens
- **Buffer remaining**: ~1,000-1,500 tokens

**Weekly Rollups**: Will likely exceed 4K token limit (7 days × 50 events). **Must use backend LLM (Claude) for weekly summaries.**

```swift
import FoundationModels

actor ActivitySummarizer {
    private let maxEventsForOnDevice = 50  // Conservative limit to stay within 4K tokens

    func generateDailySummary(events: [Event], for date: Date) async throws -> String {
        // Check if on-device is viable
        guard events.count <= maxEventsForOnDevice else {
            // Too many events, fall back to backend
            return try await generateViaBackend(events: events, date: date)
        }

        let session = LanguageModelSession()

        let prompt = """
        Summarize this person's productivity for \(date.formatted()):

        Completed:
        \(formatCompletions(events))

        Started:
        \(formatActivations(events))

        Write 2-3 sentences highlighting key accomplishments. Be specific but concise.
        """

        let response = try await session.respond(to: prompt)
        return response.content
    }
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

#### 3.3.4 Summary Caching & Invalidation

**Cache Storage:**
- Summaries are cached in `ActivitySummary` SwiftData model
- Cache key: date string (YYYY-MM-DD or YYYY-Www) + summary type

**Precise Invalidation Rules:**
| Trigger | Action | Rationale |
|---------|--------|-----------|
| New event in cached day | Mark `isStale = true` | Summary no longer reflects reality |
| Event deleted/modified | Mark `isStale = true` | Summary references outdated info |
| Model version changes | Invalidate all | New model may produce better summaries |
| Day becomes "yesterday" | Keep valid | Past days don't change |
| Manual refresh requested | Force regenerate | User wants fresh summary |

**Staleness Definition:**
A summary is stale when `eventCount` differs from actual events for that period, OR when the `generatedAt` timestamp is before the most recent event timestamp in that period.

**Regeneration Strategy:**
- Background regeneration triggered when stale summary scrolls into view
- Prefetch upcoming summaries during idle time (see 3.6.4)
- Never block UI on summary generation - show template fallback immediately
- TTL: None for past days; Today's summary expires after 2 hours of inactivity

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
3. **Offline Summary Generation**: On-device LLM works offline (iOS 26+)
4. **Fallback**: Template summaries always available offline
5. **Sync**: No activity-specific sync needed—events sync via existing mechanism

### 3.6 Performance Considerations

#### 3.6.1 Query Optimization

```swift
// Efficient query for daily events
@Query(
    filter: #Predicate<Event> { event in
        event.timestamp >= dayStart &&
        event.timestamp < dayEnd &&
        (event.type == "stack.completed" ||
         event.type == "task.completed" ||
         event.type == "stack.activated" ||
         event.type == "task.activated")
    },
    sort: \Event.timestamp,
    order: .reverse
) private var dayEvents: [Event]
```

#### 3.6.2 Lazy Loading

- Load 7 days initially
- Fetch more on scroll (pagination)
- Prefetch next batch when approaching end
- Target: <500ms load time for initial view

#### 3.6.3 Summary Generation Timing

- **Never block UI**: Show template summary immediately, enhance with LLM async
- Cache aggressively (past summaries don't change)
- Background generation during idle time
- Today's summary regenerates on significant events or every 2 hours

#### 3.6.4 Prefetch Strategy

To avoid jank when cards become visible, implement proactive prefetching:

```swift
actor SummaryPrefetcher {
    private var prefetchQueue: Set<String> = []  // Date strings

    /// Called when user opens Activity tab
    func prefetchVisibleRange(dates: [Date]) async {
        // Prefetch today + yesterday + next 3 visible days
        let priorityDates = dates.prefix(5)

        for date in priorityDates {
            let key = date.ISO8601DayString
            guard !prefetchQueue.contains(key) else { continue }
            prefetchQueue.insert(key)

            Task.detached(priority: .utility) {
                await ActivitySummaryService.shared.ensureSummaryExists(for: date)
            }
        }
    }

    /// Called during scroll deceleration
    func prefetchUpcoming(direction: ScrollDirection, visibleDates: [Date]) async {
        let upcomingDates = direction == .down
            ? visibleDates.suffix(2).map { $0.addingDays(-1) }  // Older dates
            : visibleDates.prefix(2).map { $0.addingDays(1) }   // Newer dates

        for date in upcomingDates {
            await prefetchSingle(date: date)
        }
    }
}
```

**Prefetch Triggers:**
1. **Tab appearance**: Prefetch today + yesterday + next 3 days
2. **Scroll deceleration**: Prefetch 2 days in scroll direction
3. **App background**: Prefetch tomorrow's template (for next-day opening)
4. **Idle detection**: After 30s idle, prefetch next week's templates

### 3.7 Error Handling

#### 3.7.1 Error Categories & Recovery

| Error Type | User Impact | Recovery Strategy | UX Treatment |
|------------|-------------|-------------------|--------------|
| On-device LLM unavailable | No enhanced summaries | Fall back to backend, then template | Silent fallback, no error shown |
| Backend LLM timeout | Delayed enhanced summary | Retry with backoff, show template | "Generating summary..." → template |
| Backend LLM error (500) | No enhanced summary | Log, show template, retry later | Silent fallback |
| Network offline | No backend fallback | Use on-device or template | Offline indicator in toolbar |
| SwiftData query fails | No activity shown | Retry, show error state if persistent | "Couldn't load activity. Tap to retry." |
| Summary generation crash | Corrupted cache | Clear cache for that date, regenerate | Silent recovery |

#### 3.7.2 Graceful Degradation Tiers

```
Tier 1 (Best): On-device LLM summary
    ↓ fallback
Tier 2: Backend LLM summary (Claude)
    ↓ fallback
Tier 3: Template summary ("You completed X tasks...")
    ↓ fallback
Tier 4: Raw event list (no summary)
    ↓ fallback
Tier 5: Error state with retry
```

**Critical Principle**: The user should ALWAYS see their activity data. Summary generation failures should never prevent viewing the timeline.

#### 3.7.3 LLM-Specific Error Handling

```swift
actor ActivitySummarizer {
    func generateSummary(for date: Date) async -> SummaryResult {
        // Try on-device first
        if let onDeviceResult = try? await generateOnDevice(date: date) {
            return .success(onDeviceResult, source: .onDevice)
        }

        // Try backend
        if networkMonitor.isConnected {
            do {
                let backendResult = try await generateViaBackend(date: date)
                return .success(backendResult, source: .backend)
            } catch {
                logger.error("Backend LLM failed: \(error)")
                // Continue to template fallback
            }
        }

        // Template fallback (always works)
        let template = generateTemplateSummary(for: date)
        return .success(template, source: .template)
    }
}
```

### 3.8 Event Inclusion Rules

#### 3.8.1 What Counts as an "Accomplishment"?

| Event Type | Included | Rationale |
|------------|----------|-----------|
| `stack.completed` | **Yes** | Core accomplishment - finished a project |
| `task.completed` | **Yes** | Core accomplishment - finished a unit of work |
| `stack.activated` | **Yes** | Shows work started (context for what was in progress) |
| `task.activated` | **Yes** | Shows task focus |
| `stack.created` | **Optional** | Can indicate planning activity |
| `task.created` | **No** | Too noisy, doesn't indicate accomplishment |
| `stack.deactivated` | **No** | Pausing isn't an accomplishment |
| `task.deactivated` | **No** | Pausing isn't an accomplishment |
| `attachment.added` | **Optional** | Minor, but can be included for completeness |
| `stack.deleted` | **No** | Negative action, not an accomplishment |

#### 3.8.2 Filtering Logic

```swift
extension Event {
    var isActivityFeedWorthy: Bool {
        switch type {
        case "stack.completed", "task.completed",
             "stack.activated", "task.activated":
            return true
        case "stack.created", "attachment.added":
            return UserDefaults.showMinorEvents  // User preference
        default:
            return false
        }
    }
}
```

#### 3.8.3 Timezone Handling

- **Day boundaries**: Determined by user's **current local timezone**
- **Event timestamps**: Stored in UTC, converted to local for grouping
- **Edge case**: If user changes timezone, historical groupings don't change retroactively
- **Display**: Show times in local timezone with no UTC indicator

### 3.9 Privacy & Compliance

#### 3.9.1 Data Handling Principles

| Principle | Implementation |
|-----------|----------------|
| **On-device by default** | All activity data stored locally in SwiftData |
| **LLM privacy** | On-device LLM processes data locally, never transmitted |
| **Backend opt-in** | Backend LLM only used when on-device unavailable |
| **Minimal data to backend** | Only event types + entity names sent (no full descriptions) |
| **No persistent server storage** | Backend LLM requests not logged beyond operational metrics |

#### 3.9.2 Data Sent to Backend (When Fallback Used)

```json
{
    "date": "2026-01-17",
    "events": [
        { "type": "stack.completed", "name": "API Integration" },
        { "type": "task.completed", "name": "Fix login bug" }
    ]
    // Note: No descriptions, attachments, or detailed content
}
```

#### 3.9.3 GDPR/Privacy Compliance

- **Data minimization**: Only essential data for summary generation
- **Right to erasure**: Deleting activity in app removes from all local caches
- **Transparency**: Settings screen explains when backend LLM is used
- **User control**: Option to disable backend LLM fallback entirely

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
| 3 | Cross-device summary sync | Sync summaries vs. regenerate locally | Sync from backend to ensure consistency |
| 4 | Activity notifications | Daily summary notification option | Yes, opt-in "Your daily summary is ready" |
| 5 | Widget support | Show yesterday's summary in widget | Yes, small and medium widgets |
| 6 | Calendar view option | Timeline vs. calendar grid view | Timeline primary; calendar future enhancement |
| 7 | Time tracking display | Show duration in cards | Yes, if time tracking data available |

---

## 7. Success Metrics

### 7.1 Engagement Metrics
| Metric | Target | Measurement |
|--------|--------|-------------|
| **Daily Active Viewers** | >40% of DAU | % of DAU who view Activity tab at least once |
| **Card Tap Rate** | >25% | % of cards tapped for detail view |
| **Scroll Depth** | Avg 5+ days | Average number of days scrolled back per session |
| **Share Rate** | >10% | % of users who share at least one summary per week |
| **Weekly Return Rate** | >60% | % of users who view Activity 3+ days per week |

### 7.2 Performance Metrics
| Metric | Target | Degradation Threshold |
|--------|--------|----------------------|
| **Initial Load Time** | <500ms | >1s triggers investigation |
| **Template Summary** | <50ms | Always instant |
| **On-Device LLM Summary** | <3s | >5s falls back to template |
| **Backend LLM Summary** | <2s | >4s shows template while waiting |
| **Scroll Performance** | 60fps | <45fps triggers optimization |
| **Memory Usage** | <50MB | >100MB triggers investigation |

### 7.3 Satisfaction Metrics
| Metric | Target | Method |
|--------|--------|--------|
| **Standup Usefulness** | >4.0/5.0 | In-app survey: "Did Activity help with your standup?" |
| **Summary Accuracy** | >80% positive | Thumbs up/down on generated summaries |
| **Feature NPS** | >50 | Quarterly survey among Activity users |
| **Feature Retention** | >50% at D30 | % of users still using Activity 30 days after first use |

### 7.4 Quality Metrics (LLM-Specific)
| Metric | Target | Method |
|--------|--------|--------|
| **Summary Relevance** | >85% relevant | User feedback + spot checks |
| **Factual Accuracy** | 100% | Summary must match actual events |
| **Tone Consistency** | Consistent | No jarring tone shifts between days |
| **Fallback Rate** | <20% | % of summaries using template fallback |

---

## 8. Implementation Phases

> **Note on Phase Ordering**: Template summaries are implemented early (Phase 2) to ensure the feature works on all devices from day one. Backend LLM (Phase 4) comes before weekly rollups (Phase 5) because weekly summaries exceed the on-device 4K token limit and require cloud processing.

### Phase 1: MVP - Event Timeline (Crawl)
**Goal**: Basic activity visibility without any summarization

**Deliverables:**
- `ActivityFeedView` with sectioned list by day
- `ActivityRowView` for individual events
- `ActivityEmptyView` for empty/new user state
- `Event` model query for relevant types (see Section 3.8)
- Calendar day grouping (user's local timezone)
- Navigation: tap row → stack/task detail
- Activity tab in main navigation

**Success Criteria:**
- User can see all completions and activations grouped by day
- Initial load <500ms for 7 days of activity
- Empty state guides new users

### Phase 2: Daily Cards & Template Summaries (Walk)
**Goal**: Card-based UI with deterministic template summaries (no LLM)

**Deliverables:**
- `DailyActivityCard` view with summary + top items
- `DayTimelineDetailView` for drill-down
- Template summary engine:
  ```
  "You completed {n} tasks across {m} projects, including {top_item}."
  "Today: {completions} completions, {activations} activations."
  ```
- `ActivitySummary` SwiftData model for caching
- Share functionality (copy as text)
- Pull-to-refresh for today's card
- Prefetch strategy implementation

**Success Criteria:**
- Template summaries display immediately (no loading state needed)
- Feature fully functional offline
- Works on ALL devices (no iOS 26 requirement yet)

### Phase 3: On-Device LLM Enhancement (Walk)
**Goal**: Natural language summaries via Apple Foundation Models

**Deliverables:**
- `ActivitySummarizer` actor with Foundation Models integration
- Token budget management (4K limit)
- Prompt templates (see Appendix A)
- Cache management with staleness detection
- Graceful fallback to template on failure
- Background summary generation with prefetch

**Requirements:**
- iOS 26+ with Apple Intelligence enabled
- Apple Intelligence-compatible device (iPhone 15 Pro+, M-series Macs)

**Success Criteria:**
- LLM summary generation <3 seconds
- Silent fallback to template if LLM unavailable
- No UI jank during generation

### Phase 4: Backend LLM Service (Walk)
**Goal**: Cloud LLM for devices without on-device capability and weekly rollups

**Backend Deliverables:**
- `POST /apps/{app_id}/activity/summarize` endpoint
- Claude integration for summary generation
- Rate limiting: 10 requests/user/hour
- Response caching (24 hours for past days)
- Cost monitoring and alerts

**iOS Deliverables:**
- Backend fallback when on-device unavailable
- Network error handling with retry
- Settings toggle: "Use cloud for enhanced summaries"

**Success Criteria:**
- Backend responds in <2 seconds
- Graceful degradation when backend unavailable
- Privacy disclosure in Settings

### Phase 5: Weekly Rollups (Run)
**Goal**: Weekly summary cards with cloud-powered aggregation

**Deliverables:**
- `WeeklyActivityCard` view
- Weekly summary generation (via backend - exceeds on-device limits)
- Sunday night background generation
- Weekly drill-down → daily cards
- Metrics: total completions, top projects, time tracked

**Dependencies:**
- Phase 4 (Backend LLM) - required for weekly summaries

**Success Criteria:**
- Weekly card appears Monday morning
- Summary covers all 7 days accurately
- Drill-down navigation works smoothly

### Phase 6: Filtering & Polish (Run)
**Goal**: Filter by tags, sources, time range

**Deliverables:**
- `ActivityFilterView` sheet
- Tag filtering
- Time range filtering (This Week, This Month, Custom)
- Event type filtering (completions, activations, etc.)
- Active filter indicator
- Clear filters action
- Filter state persistence (session-only)

**Success Criteria:**
- Filters apply instantly (<100ms)
- Clear visual indication of active filters
- Summaries regenerate for filtered view

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

### 9.1 Core (Required for MVP)
| Dependency | Status | Notes |
|------------|--------|-------|
| `Event` model | ✅ Exists | Uses existing sync system |
| SwiftUI List/ScrollView | ✅ Available | Standard iOS framework |
| SwiftData | ✅ Available | For `ActivitySummary` caching |
| Tab navigation | ✅ Exists | Add Activity tab |

### 9.2 On-Device LLM (Phase 3)
| Dependency | Requirement | Fallback |
|------------|-------------|----------|
| iOS 26+ | Required | Template summary |
| Apple Intelligence enabled | Required | Template summary |
| Compatible device | iPhone 15 Pro+, M-series Mac | Template summary |
| Foundation Models framework | Xcode 26+ | N/A |

### 9.3 Backend LLM (Phase 4)
| Dependency | Requirement | Notes |
|------------|-------------|-------|
| Backend API | `POST /activity/summarize` | New endpoint |
| Claude API | Anthropic API key | For summary generation |
| Rate limiting | Redis or similar | Prevent abuse |
| Network connectivity | Required | Falls back to template offline |

### 9.4 Future Integrations (Phase 7+)
- External System Integrations feature (see ROADMAP Section 1)
- Linear, GitHub OAuth connections
- Webhook infrastructure for external events

---

## 10. Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| **On-device 4K token limit exceeded** | High | Medium | Cap events at 50/day; use backend for busy days |
| **LLM summary quality varies** | Medium | Medium | Template fallback; user feedback mechanism |
| **On-device LLM not available** | Medium | High | ~50% of users on older devices; backend + template fallback |
| **iOS 26 adoption slow** | Medium | Medium | Template-first approach works on all iOS versions |
| **Large event history impacts performance** | Medium | Low | Lazy loading; limit initial query to 30 days |
| **Summary generation costs (backend)** | Medium | Medium | Cache aggressively; rate limit 10/user/hour |
| **Privacy concerns with backend LLM** | High | Low | On-device primary; opt-in disclosure; minimal data sent |
| **Users don't discover the feature** | Medium | Medium | Onboarding tooltip; tab badge for first week |
| **Summary doesn't match user's perception** | Low | Low | Show raw events; allow feedback; template fallback |
| **Weekly rollups require backend** | Medium | High | Design constraint—weekly always uses cloud LLM |
| **Timezone edge cases** | Low | Low | Use local timezone; clear date headers |

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
