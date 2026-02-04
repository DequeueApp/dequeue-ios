# Activity Feed / Daily Accomplishments - PRD

**Feature:** Activity Feed & Daily Summaries  
**Author:** Ada (Dequeue Engineer)  
**Date:** 2026-02-03  
**Status:** Draft  
**Related:** ROADMAP.md Section 2

## Problem Statement

Users complete tasks, activate stacks, and make progress every day - but **they have no way to see what they've accomplished**. This creates several problems:

1. **Lack of Motivation**: No sense of accomplishment or progress over time
2. **Poor Memory**: "What did I do yesterday?" requires scrolling through Stacks
3. **Status Updates**: No easy way to generate standup reports or weekly summaries
4. **Lost Context**: Can't remember when you worked on something
5. **No Celebration**: Completing tasks feels hollow without reflection

**User pain points:**
- "I know I did a lot this week, but I can't remember what"
- "My manager asks for a weekly update - I have to reconstruct it from memory"
- "I want to see my productivity trends over time"
- "Did I work on that project last week or the week before?"

**Competitor benchmark:**
- Things 3: "Logbook" showing completed items with timeline
- Todoist: "Productivity" view with karma points and charts
- Streaks: Visual calendar showing streaks
- Done: Daily/weekly summaries with photos

**Without an activity feed, users lose the satisfaction of seeing their progress - a major engagement driver.**

## Solution

A reverse-chronological feed of user activity, organized by day, with AI-generated summaries for quick scanning.

**Key Principles:**
1. **Glanceable**: Quick visual scan shows what you did each day
2. **Detailed on demand**: Tap to drill into timeline of events
3. **AI-enhanced**: LLM summaries make sense of raw data
4. **Celebration-focused**: Highlight accomplishments, not just tasks
5. **Actionable**: Use for standups, reviews, reflection

## Features

### 1. Activity Feed (Main View)

#### Layout

```
┌─────────────────────────────────────┐
│  Activity                      🔍   │  ← Tab title + search
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 📅 Today - Feb 3             │   │
│  │                              │   │
│  │ ✨ Great progress today!     │   │  ← AI summary
│  │ You completed 5 tasks across │   │
│  │ 2 projects and stayed focused│   │
│  │ on API Integration.          │   │
│  │                              │   │
│  │ 🎯 Completed:                │   │  ← Key metrics
│  │ • 5 tasks                    │   │
│  │ • 1 stack (API Integration)  │   │
│  │                              │   │
│  │ ⏱️ Active time: 4h 32m       │   │
│  │                              │   │
│  │ [View Timeline →]            │   │  ← Drill-down
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 📅 Yesterday - Feb 2         │   │
│  │ ... (similar card)           │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 📊 This Week                 │   │  ← Weekly rollup
│  │ ... (weekly summary)         │   │
│  └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

#### Daily Card Content

**Header:**
- Date (relative: "Today", "Yesterday", "Monday", or full date)
- Day of week

**AI Summary** (2-3 sentences):
- Natural language summary of the day
- Examples:
  - "Great progress today! You completed 5 tasks across 2 projects."
  - "Focused day - you worked exclusively on API Integration for 6 hours."
  - "Light activity - you activated Work but didn't complete any tasks."
  - "You tackled 3 different stacks today, staying flexible."

**Key Metrics:**
- ✅ Tasks completed: X
- 🎯 Stacks completed: X
- 📦 Stacks activated: X
- ⏱️ Active time: Xh Xm (calculated from activation/deactivation events)

**Primary Action:**
- "View Timeline" button → Navigates to detail view

#### Weekly Rollup Card

Every Monday, show a card for the previous week:

```
┌─────────────────────────────────────┐
│ 📊 Last Week (Jan 27 - Feb 2)      │
│                                     │
│ 🎉 Productive week! You completed  │
│ 23 tasks across 5 projects and     │
│ shipped the entire API Integration │
│ stack.                              │
│                                     │
│ Highlights:                         │
│ • Completed: API Integration ✅     │
│ • 23 tasks finished                 │
│ • 8h 15m average daily active time  │
│                                     │
│ [View Week →]                       │
└─────────────────────────────────────┘
```

**Appears:** Monday mornings (or first app open after Sunday)

#### Empty States

**No activity today:**
```
📅 Today - Feb 3

No activity yet today.
Create a Stack or activate one to get started!

[Go to Stacks]
```

**No activity this week:**
```
📊 This Week

Quiet week so far.
```

### 2. Timeline Detail View

When user taps "View Timeline" on a daily card:

```
┌─────────────────────────────────────┐
│  ← Today - Feb 3                   │  ← Back button
├─────────────────────────────────────┤
│                                     │
│  🌅 Morning                         │
│  ──────────────────────────────────│
│  9:15 AM  🟢 Activated: API Integr.│  ← Event
│  9:30 AM  ✅ Completed: Write tests│
│  10:45 AM ✅ Completed: Fix bug    │
│                                     │
│  🌤️ Afternoon                       │
│  ──────────────────────────────────│
│  2:00 PM  🟢 Activated: Personal   │
│  2:15 PM  ✅ Completed: Buy milk   │
│  3:00 PM  🟢 Activated: API Integr.│
│  4:30 PM  ✅ Completed: Deploy     │
│                                     │
│  🌙 Evening                         │
│  ──────────────────────────────────│
│  7:00 PM  🔴 Deactivated: API Int. │
│                                     │
└─────────────────────────────────────┘
```

**Grouping:**
- Events grouped by time of day: Morning (6-12), Afternoon (12-6), Evening (6-12), Night (12-6)

**Event Types:**
| Event | Icon | Color | Description |
|-------|------|-------|-------------|
| Stack activated | 🟢 | Green | "Activated: [Stack]" |
| Stack deactivated | 🔴 | Red | "Deactivated: [Stack]" |
| Task completed | ✅ | Blue | "Completed: [Task]" |
| Stack completed | 🎉 | Gold | "Completed: [Stack]" |
| Task created | ➕ | Gray | "Created: [Task]" |
| Stack created | 📦 | Gray | "Created: [Stack]" |

**Interaction:**
- Tap event → Navigate to that Stack/Task detail
- Long-press → Quick actions (e.g., "Reactivate Stack")

**Filtering:**
- "All Events" vs "Completions Only" toggle at top
- Filter by Stack (show events for specific Stack only)

### 3. AI Summary Generation

#### When to Generate

**Options:**
1. **On-demand** (when user views Activity tab) - More flexible, always fresh
2. **Background cron** (nightly at 11 PM) - Pre-computed, faster to display
3. **Hybrid** (generate on first view of day, cache for 24h)

**Recommendation:** Hybrid - generate when user first views the feed, cache for 24 hours.

#### Where to Generate

**Option A: On-device (iOS)**
- Pros: Privacy (no data sent to server), fast
- Cons: Requires on-device LLM (limited capability), battery drain

**Option B: Backend API**
- Pros: More capable LLM (GPT-4, Claude), no device resource usage
- Cons: Network required, privacy concern (sending task data to LLM)

**Option C: Opt-in server-side**
- Pros: Best UX for users who opt in, privacy-preserving for those who don't
- Cons: Two code paths

**Recommendation:** Start with **Option B** (backend API) for MVP. Add opt-out setting for privacy-conscious users. Consider on-device in Phase 2 when Apple Intelligence matures.

#### Summary Generation Prompt

**System prompt:**
```
You are an AI assistant helping users reflect on their daily work.
Given a list of events (stack activations, task completions),
generate a 2-3 sentence natural language summary that:
- Highlights accomplishments
- Is encouraging and positive
- Mentions specific stacks or tasks by name
- Keeps tone professional but friendly
```

**User prompt:**
```
Events for Feb 3, 2026:
- 9:15 AM: Activated Stack "API Integration"
- 9:30 AM: Completed Task "Write integration tests"
- 10:45 AM: Completed Task "Fix authentication bug"
- 2:00 PM: Activated Stack "Personal"
- 2:15 PM: Completed Task "Buy groceries"
- 3:00 PM: Activated Stack "API Integration"
- 4:30 PM: Completed Task "Deploy to staging"
- 7:00 PM: Deactivated Stack "API Integration"

Summarize this day in 2-3 sentences. Be specific and encouraging.
```

**Example output:**
```
Great progress today! You spent most of your day on API Integration,
completing 3 key tasks including fixing an authentication bug and
deploying to staging. You also knocked out a personal errand in the
afternoon—nice balance between work and life!
```

**Caching:**
- Store summary in database: `daily_summaries` table
- Schema: `{ userId, date, summary, generatedAt }`
- Regenerate only if user requests (e.g., "Refresh summary")

#### Privacy Considerations

**What's sent to LLM:**
- Stack titles
- Task titles
- Event types (activated, completed)
- Timestamps

**NOT sent:**
- Task descriptions (too detailed, may contain sensitive info)
- Attachments
- Comments/notes

**User control:**
- Setting to disable AI summaries: "Use generic summaries instead"
- Generic summary template: "You completed {X} tasks across {Y} stacks today."

### 4. Export / Sharing

**Use cases:**
- Weekly standup report
- Performance review documentation
- Client billing (time tracking)
- Personal journaling

**Export options:**
- Copy to clipboard (Markdown)
- Share as PDF
- Share as text
- Share as image (screenshot of card)

**Markdown format example:**
```markdown
# Activity Summary - Feb 3, 2026

Great progress today! You spent most of your day on API Integration,
completing 3 key tasks including fixing an authentication bug and
deploying to staging.

## Metrics
- ✅ 4 tasks completed
- 📦 2 stacks activated
- ⏱️ 5h 30m active time

## Timeline
**Morning**
- 9:15 AM: Activated API Integration
- 9:30 AM: Completed "Write integration tests"

**Afternoon**
- 2:00 PM: Activated Personal
- 2:15 PM: Completed "Buy groceries"
...
```

**Share sheet UI:**
```swift
Button("Share") {
    let markdown = generateMarkdown(for: day)
    let activityVC = UIActivityViewController(
        activityItems: [markdown],
        applicationActivities: nil
    )
    present(activityVC)
}
```

## Technical Design

### Data Model

**No new schema required** - Activity Feed is a **read-only view** of existing events.

**Data sources:**
1. `Stack.activatedAt` / `deactivatedAt` → Stack activation/deactivation
2. `Task.completedAt` → Task completions
3. `Stack.completedAt` → Stack completions
4. Event history (if stored) → Full timeline reconstruction

**Derived metrics:**
- Active time: Sum of (deactivation - activation) intervals
- Tasks completed: Count of tasks with `completedAt` in date range
- Stacks activated: Distinct stacks with `activatedAt` in date range

### Query Logic (SwiftData)

**Fetch events for a specific day:**
```swift
func fetchActivity(for date: Date) async throws -> [ActivityEvent] {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: date)
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
    
    var events: [ActivityEvent] = []
    
    // Fetch stack activations
    let activatedStacks = try await modelContext.fetch(
        FetchDescriptor<Stack>(
            predicate: #Predicate { stack in
                stack.activatedAt >= startOfDay && stack.activatedAt < endOfDay
            }
        )
    )
    events += activatedStacks.map { stack in
        ActivityEvent(
            type: .stackActivated,
            timestamp: stack.activatedAt,
            title: stack.title,
            stackId: stack.id
        )
    }
    
    // Fetch completed tasks
    let completedTasks = try await modelContext.fetch(
        FetchDescriptor<Task>(
            predicate: #Predicate { task in
                task.completedAt >= startOfDay && task.completedAt < endOfDay
            }
        )
    )
    events += completedTasks.map { task in
        ActivityEvent(
            type: .taskCompleted,
            timestamp: task.completedAt,
            title: task.title,
            taskId: task.id,
            stackId: task.stack?.id
        )
    }
    
    // Sort by timestamp
    return events.sorted { $0.timestamp < $1.timestamp }
}
```

**Calculate active time:**
```swift
func calculateActiveTime(for date: Date) async throws -> TimeInterval {
    let stacks = try await fetchActivity(for: date)
        .filter { $0.type == .stackActivated || $0.type == .stackDeactivated }
    
    var totalTime: TimeInterval = 0
    var activeStack: ActivityEvent? = nil
    
    for event in stacks.sorted(by: { $0.timestamp < $1.timestamp }) {
        if event.type == .stackActivated {
            activeStack = event
        } else if event.type == .stackDeactivated, let start = activeStack {
            totalTime += event.timestamp.timeIntervalSince(start.timestamp)
            activeStack = nil
        }
    }
    
    // If stack is still active at end of day, count until now
    if let start = activeStack {
        totalTime += Date().timeIntervalSince(start.timestamp)
    }
    
    return totalTime
}
```

### AI Summary API

**Backend endpoint:**
```
POST /v1/activity/summary
Authorization: Bearer {jwt}

Request:
{
  "date": "2026-02-03",
  "events": [
    { "type": "stack_activated", "timestamp": "2026-02-03T14:15:00Z", "title": "API Integration" },
    { "type": "task_completed", "timestamp": "2026-02-03T14:30:00Z", "title": "Write tests" }
  ]
}

Response:
{
  "summary": "Great progress today! You completed 5 tasks...",
  "generatedAt": "2026-02-03T22:00:00Z"
}
```

**Backend implementation (Go):**
```go
func (s *ActivityService) GenerateSummary(ctx context.Context, req *GenerateSummaryRequest) (*GenerateSummaryResponse, error) {
    // Build LLM prompt
    prompt := buildSummaryPrompt(req.Date, req.Events)
    
    // Call LLM (OpenAI, Anthropic, etc.)
    summary, err := s.llmClient.Complete(ctx, prompt)
    if err != nil {
        return nil, err
    }
    
    // Cache summary
    err = s.cache.Set(ctx, cacheKey(req.UserID, req.Date), summary, 24*time.Hour)
    if err != nil {
        log.Warn("Failed to cache summary", "error", err)
    }
    
    return &GenerateSummaryResponse{
        Summary: summary,
        GeneratedAt: time.Now(),
    }, nil
}
```

**Caching strategy:**
- Cache for 24 hours (summary won't change after day ends)
- Invalidate if user adds/completes tasks retroactively
- Store in Redis or database table

### View Architecture (SwiftUI)

**New Views:**
1. `ActivityFeedView` (main feed, list of daily cards)
2. `DailyActivityCard` (individual day card with summary)
3. `WeeklyActivityCard` (weekly rollup card)
4. `ActivityTimelineView` (detailed timeline for a day)
5. `ActivityEventRow` (individual event in timeline)

**ViewModels:**
```swift
@Observable
class ActivityFeedViewModel {
    var dailyActivities: [DailyActivity] = []
    var isLoading = false
    var error: Error?
    
    func loadRecentActivity() async {
        isLoading = true
        defer { isLoading = false }
        
        let last30Days = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        
        dailyActivities = try await (0..<30).asyncMap { dayOffset in
            let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date())!
            return try await fetchDailyActivity(for: date)
        }
    }
    
    func fetchDailyActivity(for date: Date) async throws -> DailyActivity {
        let events = try await activityService.fetchActivity(for: date)
        let activeTime = try await activityService.calculateActiveTime(for: date)
        
        let summary = try await activityService.fetchOrGenerateSummary(for: date, events: events)
        
        return DailyActivity(
            date: date,
            events: events,
            summary: summary,
            tasksCompleted: events.filter { $0.type == .taskCompleted }.count,
            stacksActivated: Set(events.filter { $0.type == .stackActivated }.map { $0.stackId }).count,
            activeTime: activeTime
        )
    }
}

struct DailyActivity: Identifiable {
    let id = UUID()
    let date: Date
    let events: [ActivityEvent]
    let summary: String
    let tasksCompleted: Int
    let stacksActivated: Int
    let activeTime: TimeInterval
}
```

---

## Acceptance Criteria

### Functional
- [ ] Activity tab shows list of daily cards (last 30 days)
- [ ] Each card shows date, AI summary, key metrics
- [ ] Tap card → Navigate to timeline detail view
- [ ] Timeline shows events grouped by time of day (Morning/Afternoon/Evening)
- [ ] Tap event → Navigate to Stack/Task detail
- [ ] Weekly rollup card appears on Mondays
- [ ] Empty state handled (no activity today)
- [ ] Export daily summary as Markdown
- [ ] Share sheet works (copy, PDF, image)

### AI Summary
- [ ] Backend API generates summaries via LLM
- [ ] Summaries cached for 24 hours
- [ ] Summaries are 2-3 sentences, specific, encouraging
- [ ] Setting to disable AI summaries (use generic template)
- [ ] Privacy: Only titles sent to LLM, not descriptions

### Performance
- [ ] Feed loads in <2 seconds for 30 days of activity
- [ ] Scrolling is smooth (60 fps)
- [ ] Timeline detail view loads instantly (<500ms)

### Design
- [ ] Cards visually consistent with app design
- [ ] AI summaries feel natural, not robotic
- [ ] Event icons clear and intuitive
- [ ] Dark mode support
- [ ] Responsive to different screen sizes

---

## Edge Cases

1. **No activity for days**: Show empty cards, don't skip dates
2. **Very busy day (100+ events)**: Paginate timeline, don't show all at once
3. **LLM API failure**: Fall back to generic template summary
4. **User completed task yesterday, views today**: Summary refreshes if cache expired
5. **User in different timezone**: Use local timezone for "today", "yesterday"
6. **User deletes completed task**: Remove from activity feed (or mark as "deleted")
7. **Multiple stacks activated same day**: Summary mentions all of them

---

## Testing Strategy

### Unit Tests
```swift
@Test func fetchActivityForDayReturnsEvents() async throws {
    let stack = Stack(title: "Work", activatedAt: Date(), ...)
    let task = Task(title: "Test", completedAt: Date(), ...)
    await modelContext.insert(stack)
    await modelContext.insert(task)
    
    let activity = try await activityService.fetchActivity(for: Date())
    #expect(activity.count == 2)
}

@Test func calculateActiveTimeCorrect() async throws {
    let stack = Stack(title: "Work")
    stack.activatedAt = Date().addingTimeInterval(-3600)  // 1 hour ago
    stack.deactivatedAt = Date()
    await modelContext.insert(stack)
    
    let activeTime = try await activityService.calculateActiveTime(for: Date())
    #expect(activeTime == 3600)
}
```

### Integration Tests
- Create mock activity data (stacks, tasks, events)
- Verify daily cards rendered correctly
- Verify timeline shows events in order
- Verify AI summary API called and cached

### Manual Testing
- Use app for a few days, generate real activity
- Check feed reflects reality
- Test export (Markdown, PDF)
- Test on different screen sizes
- Test with very busy days (100+ events)

---

## Implementation Plan

**Estimated: 3-4 days**

### Day 1: Data Layer & API (6-8 hours)
1. Create `ActivityService` for querying events (2 hours)
2. Implement active time calculation (1 hour)
3. Create backend `/activity/summary` API endpoint (2 hours)
4. Implement LLM prompt generation and caching (2 hours)
5. Test API with sample data (1 hour)

### Day 2: UI - Feed & Cards (6-8 hours)
1. Create `ActivityFeedView` (main list) (2 hours)
2. Build `DailyActivityCard` component (2 hours)
3. Build `WeeklyActivityCard` component (1 hour)
4. Implement empty states (1 hour)
5. Test on device with real data (1 hour)

### Day 3: UI - Timeline & Details (4-6 hours)
1. Create `ActivityTimelineView` (2 hours)
2. Build `ActivityEventRow` component (1 hour)
3. Implement event grouping (Morning/Afternoon/etc.) (1 hour)
4. Add navigation from event to Stack/Task (1 hour)

### Day 4: Export & Polish (4-6 hours)
1. Implement Markdown export (1 hour)
2. Add share sheet integration (1 hour)
3. Unit tests for activity queries (1 hour)
4. Integration tests (1 hour)
5. Manual testing and polish (1 hour)
6. PR review & merge (1 hour + CI time)

**Total: 20-28 hours** (spread across 4 days)

---

## Dependencies

- ✅ Backend API for AI summary generation (new endpoint)
- ✅ LLM API access (OpenAI, Anthropic, or similar)
- ✅ Redis or caching layer for summary storage
- ⚠️ Event history data (may need to backfill if not stored)

**Blockers:**
- Backend `/activity/summary` endpoint (need to implement)

---

## Out of Scope

- GitHub integration (commits, PRs) - Phase 2
- Calendar integration (meetings) - Phase 2
- Email integration (sent/received) - Phase 2
- Photo attachments in feed - Phase 2
- Productivity charts/graphs - separate feature
- Streaks/gamification - separate feature

---

## Success Metrics

**Adoption:**
- % of users who view Activity tab weekly
- % of users who export summaries

**Engagement:**
- Average time spent in Activity tab per session
- % of users who tap into timeline details

**Retention:**
- Retention lift for users who regularly view Activity feed vs those who don't
- Hypothesis: Seeing progress increases motivation and retention

**Target:**
- 40%+ of users view Activity tab at least once per week
- 20%+ of users export summaries for standups/reviews

---

**Next Steps:**
1. Review PRD with Victor
2. Create implementation ticket (DEQ-XXX)
3. Implement backend `/activity/summary` API first (blocker)
4. Implement iOS UI when CI responsive
5. Ship and monitor adoption + engagement

**Reflection drives motivation.** Let's help users celebrate their progress. 🎉
