# PRD: Navigation Redesign & Activity Feed

**Status**: Draft
**Author**: Claude (with Victor)
**Created**: 2026-01-05
**Last Updated**: 2026-01-05
**Issue**: TBD (Linear)

---

## Executive Summary

Redesign the main navigation structure to consolidate three separate tabs (Home, Drafts, Completed) into a single unified "Stacks" tab with a segmented control, freeing up space for a new Activity Feed tab that shows daily accomplishments. This refactor simplifies navigation, reduces tab bar clutter, and introduces a valuable new feature for tracking what you've done.

**Key Changes:**
- **Consolidate tabs**: Home + Drafts + Completed → Single "Stacks" tab with pill/segment UI
- **New Activity tab**: Daily accomplishments feed (MVP: raw event list, future: LLM summaries)
- **Remove drag-to-reorder**: Stacks sorted by creation date (newest first) instead
- **Third tab placeholder**: Reserved for future Attachments & Links Gallery
- **Tab count**: 5 tabs → 4 tabs (Stacks, Activity, [Placeholder], Settings)
- **Active Stack banner**: Remains omnipresent across all tabs (unchanged)

**Phased Approach (Crawl/Walk/Run):**
- **Crawl (MVP)**: Simple event list showing yesterday's activity
- **Walk**: Backend-generated daily summaries, weekly rollups
- **Run**: Full LLM integration, cross-platform consistency, rich cards

---

## 1. Overview

### 1.1 Problem Statement

The current navigation has several issues:

1. **Tab sprawl**: Three separate tabs (Home, Drafts, Completed) for what is conceptually the same thing—stacks in different states. Users must navigate between tabs to see their full picture.

2. **No accomplishments view**: Users have no easy way to see what they've done. The event log exists in the debug settings, but there's no user-facing "what did I accomplish today/this week?" view.

3. **Unused features**: Drag-to-reorder stacks exists but provides little value in practice. Manual ordering adds friction without clear benefit.

4. **Wasted tab space**: With three tabs for stacks and one for settings, the tab bar is cluttered without providing proportional value.

### 1.2 Proposed Solution

**Part 1: Unified Stacks Tab**
- Consolidate Home, Drafts, and Completed into a single "Stacks" tab
- Use a horizontal pill/segmented control at the top to switch between:
  - "In Progress" (current active stacks - default view)
  - "Drafts" (work-in-progress drafts)
  - "Completed" (finished stacks)
- Remove drag-to-reorder; sort by creation date (newest first)

**Part 2: Activity Feed Tab**
- New tab showing daily accomplishments
- MVP: Simple chronological list of events from recent days
- Future: LLM-generated summaries, weekly rollups, rich cards

**Part 3: Placeholder Tab**
- Reserve third tab for future "Gallery" feature (Attachments & Links)
- Can show coming-soon state or be hidden initially

### 1.3 Goals

- Simplify navigation by reducing conceptual overhead
- Provide visibility into daily/weekly accomplishments
- Remove unused complexity (drag-to-reorder)
- Create foundation for future features (Gallery, LLM summaries)
- Maintain platform parity (iOS, iPadOS, macOS)

### 1.4 Non-Goals

- Full LLM summarization (future phase)
- Backend changes for activity aggregation (future phase)
- Complex filtering/search within stacks (future)
- Attachments & Links Gallery implementation (separate PRD)
- Android/web implementations (future)

---

## 2. User Stories

### 2.1 Stacks Tab

1. **As a user**, I want to see all my stacks in one place so I don't have to switch between tabs.
2. **As a user**, I want to quickly filter between in-progress, drafts, and completed stacks.
3. **As a user**, I want my stacks sorted by newest first so recent work is at the top.
4. **As a user**, I want the same stacks experience on iOS, iPadOS, and macOS.

### 2.2 Activity Feed Tab

1. **As a user**, I want to see what I accomplished yesterday so I can remember my progress.
2. **As a user**, I want to see a list of recent completions and activations.
3. **As a user**, I want to tap on an activity item to navigate to that stack/task.
4. **As a user**, I want to scroll back through previous days' activity.

### 2.3 Edge Cases

- User has no stacks in a category → Show appropriate empty state
- User has no activity for a day → Skip that day or show "No activity"
- User switches segments rapidly → Smooth transition, no flicker
- Offline viewing → Activity based on local events, syncs when online

---

## 3. Technical Design

### 3.1 Navigation Structure Changes

**Current Structure:**
```
TabView
├── Tab 0: HomeView (active stacks)
├── Tab 1: DraftsView
├── Tab 2: [Add button - triggers sheet]
├── Tab 3: CompletedStacksView
└── Tab 4: SettingsView
```

**New Structure:**
```
TabView
├── Tab 0: StacksView (unified with segment control)
│   ├── Segment: "In Progress" → active stacks
│   ├── Segment: "Drafts" → draft stacks
│   └── Segment: "Completed" → completed stacks
├── Tab 1: ActivityFeedView
├── Tab 2: [Add button - triggers sheet] OR GalleryPlaceholderView
├── Tab 3: SettingsView
└── (Tab 4 removed)
```

**Design Decision**: Keep the "Add" button as a center tab that triggers a sheet, or move it to a toolbar button and use that tab slot for Gallery placeholder. Recommend: Keep Add as center tab for discoverability.

### 3.2 Stacks Tab Implementation

#### 3.2.1 StacksView (New Unified View)

```swift
struct StacksView: View {
    enum StackFilter: String, CaseIterable {
        case inProgress = "In Progress"
        case drafts = "Drafts"
        case completed = "Completed"
    }

    @State private var selectedFilter: StackFilter = .inProgress

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control / pill picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(StackFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Content based on selection
                switch selectedFilter {
                case .inProgress:
                    InProgressStacksListView()
                case .drafts:
                    DraftsStacksListView()
                case .completed:
                    CompletedStacksListView()
                }
            }
            .navigationTitle("Stacks")
        }
    }
}
```

#### 3.2.2 Sort Order Change

Remove `sortOrder` field usage for manual ordering. Update queries to sort by `createdAt` descending:

```swift
// Before
@Query(sort: \Stack.sortOrder) private var stacks: [Stack]

// After
@Query(
    filter: #Predicate<Stack> { ... },
    sort: \Stack.createdAt,
    order: .reverse
) private var stacks: [Stack]
```

**Migration Note**: The `sortOrder` field can remain in the model for now (no data migration needed), but it will no longer be used or updated. Can be removed in a future cleanup.

#### 3.2.3 Remove Drag-to-Reorder

Remove from `HomeView` (now `InProgressStacksListView`):
- Remove `.onMove(perform: moveStacks)`
- Remove `moveStacks(from:to:)` function
- Remove `StackService.updateSortOrders()` calls for reordering

### 3.3 Activity Feed Implementation

#### 3.3.1 Data Model

The Activity Feed reads from the existing `Event` model. No new models required for MVP.

```swift
// Query recent events for activity display
@Query(
    filter: #Predicate<Event> { event in
        // Filter to relevant event types
        event.type == "stack.completed" ||
        event.type == "task.completed" ||
        event.type == "stack.activated" ||
        event.type == "task.activated"
    },
    sort: \Event.timestamp,
    order: .reverse
) private var activityEvents: [Event]
```

#### 3.3.2 ActivityFeedView (MVP - Crawl Phase)

```swift
struct ActivityFeedView: View {
    @Query private var activityEvents: [Event]

    // Group events by day
    private var eventsByDay: [(Date, [Event])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: activityEvents) { event in
            calendar.startOfDay(for: event.timestamp)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(eventsByDay, id: \.0) { day, events in
                    Section(header: Text(day, style: .date)) {
                        ForEach(events) { event in
                            ActivityRowView(event: event)
                        }
                    }
                }
            }
            .navigationTitle("Activity")
        }
    }
}
```

#### 3.3.3 ActivityRowView

```swift
struct ActivityRowView: View {
    let event: Event

    var body: some View {
        HStack {
            // Icon based on event type
            Image(systemName: iconName)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading) {
                Text(eventTitle)
                    .font(.subheadline)
                Text(event.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconName: String {
        switch event.eventType {
        case .stackCompleted, .taskCompleted:
            return "checkmark.circle.fill"
        case .stackActivated, .taskActivated:
            return "play.circle.fill"
        default:
            return "circle"
        }
    }

    private var iconColor: Color {
        switch event.eventType {
        case .stackCompleted, .taskCompleted:
            return .green
        case .stackActivated, .taskActivated:
            return .blue
        default:
            return .secondary
        }
    }

    private var eventTitle: String {
        // Decode payload to get entity name
        // e.g., "Completed: Quarterly Report"
        // e.g., "Started: API Integration"
    }
}
```

### 3.4 Active Stack Banner

The Active Stack banner is a floating component that appears at the bottom of the screen (above the tab bar) showing the currently active stack. This behavior is **unchanged** from the current implementation.

**Current behavior (preserved):**
- Banner appears on all tabs when a stack is active
- Tapping the banner opens the stack detail sheet
- Tapping "empty" state navigates to Stacks tab (previously "Home")
- On iPad: Banner has max width constraint for readability
- On macOS: Banner appears at bottom of detail pane

**Implementation note:**
The `activeStackBanner` overlay in `MainTabView.swift` continues to work as-is. No changes required to this component—it will naturally appear across all tabs including the new Activity tab.

```swift
// Existing pattern in MainTabView - no changes needed
.overlay(alignment: .bottom) {
    activeStackBanner
        // ... positioning logic
}
```

### 3.5 Platform Considerations

#### iOS/iPadOS
- Segmented control uses `.pickerStyle(.segmented)`
- Tab bar remains at bottom
- Activity feed uses standard List

#### macOS
- Segmented control in toolbar or below navigation title
- Sidebar navigation (existing pattern)
- Consider using `.pickerStyle(.segmented)` or toolbar buttons

### 3.6 Future Phases (Walk/Run)

#### Walk Phase: Backend Summaries
- New backend endpoint: `GET /apps/{app_id}/activity/daily?date=2026-01-05`
- Returns pre-computed daily summary
- Backend job runs nightly to generate summaries
- Client caches summaries locally

#### Run Phase: LLM Integration
- Investigate Apple's on-device LLM capabilities (Foundation Models framework)
- Fallback to backend LLM service if on-device unavailable
- Consider cross-platform consistency (web, Android need backend)
- Daily summary generation as background task

---

## 4. UI/UX Design

### 4.1 Stacks Tab

```
┌─────────────────────────────────────────┐
│ Stacks                               🔔 │
├─────────────────────────────────────────┤
│ ┌───────────┬─────────┬───────────────┐ │
│ │In Progress│ Drafts  │  Completed    │ │  ← Segmented control
│ └───────────┴─────────┴───────────────┘ │
├─────────────────────────────────────────┤
│ Quarterly Report                      ★ │
│ Draft executive summary                 │
├─────────────────────────────────────────┤
│ API Integration                         │
│ Implement auth endpoints                │
├─────────────────────────────────────────┤
│ ...                                     │
└─────────────────────────────────────────┘
```

**Segment States:**
- Selected: Filled background, bold text
- Unselected: Clear background, regular text
- Use system `.segmented` picker style for native feel

**Note:** Active Stack banner floats at bottom of all views (see section 3.4).

### 4.2 Activity Feed Tab

```
┌─────────────────────────────────────────┐
│ Activity                                │
├─────────────────────────────────────────┤
│ TODAY                                   │
├─────────────────────────────────────────┤
│ ✓ Completed: API Integration    2:30 PM │
│ ▶ Started: Documentation        1:15 PM │
│ ✓ Completed: Fix login bug     11:00 AM │
│ ▶ Started: API Integration      9:30 AM │
├─────────────────────────────────────────┤
│ YESTERDAY                               │
├─────────────────────────────────────────┤
│ ✓ Completed: Design review      5:00 PM │
│ ▶ Started: Design review        2:00 PM │
│ ...                                     │
└─────────────────────────────────────────┘
```

**Event Types to Display (MVP):**
| Event Type | Icon | Label | Color |
|------------|------|-------|-------|
| stack.completed | checkmark.circle.fill | "Completed" | Green |
| task.completed | checkmark.circle.fill | "Completed task" | Green |
| stack.activated | play.circle.fill | "Started" | Blue |
| task.activated | play.circle.fill | "Started task" | Blue |

**Future (Walk Phase):**
```
┌─────────────────────────────────────────┐
│ Activity                                │
├─────────────────────────────────────────┤
│ ┌─────────────────────────────────────┐ │
│ │ TODAY                               │ │
│ │                                     │ │
│ │ You completed 3 tasks across 2      │ │
│ │ projects, including finishing the   │ │
│ │ API integration work.               │ │
│ │                                     │ │
│ │ ✓ API Integration                   │ │
│ │ ✓ Fix login bug                     │ │
│ │ ✓ Documentation update              │ │
│ └─────────────────────────────────────┘ │
├─────────────────────────────────────────┤
│ YESTERDAY                             → │
├─────────────────────────────────────────┤
│ ...                                     │
└─────────────────────────────────────────┘
```

### 4.3 Tab Bar

**New Tab Bar Layout (iOS):**
```
┌─────────────────────────────────────────┐
│  Stacks    Activity    (+)    Settings  │
│    📚        📊        ➕        ⚙️      │
└─────────────────────────────────────────┘
```

**Tab Icons:**
| Tab | Icon | SF Symbol |
|-----|------|-----------|
| Stacks | Stack of papers | `square.stack.3d.up` |
| Activity | Chart/timeline | `chart.bar.fill` or `clock.arrow.circlepath` |
| Add | Plus circle | `plus.circle` |
| Settings | Gear | `gear` |

**Alternative with Gallery placeholder:**
```
┌───────────────────────────────────────────────┐
│  Stacks   Activity   (+)   Gallery   Settings │
│    📚       📊       ➕      🖼️        ⚙️     │
└───────────────────────────────────────────────┘
```

### 4.4 Empty States

**Activity Feed Empty State:**
```
┌─────────────────────────────────────────┐
│                                         │
│              📊                         │
│                                         │
│        No Activity Yet                  │
│                                         │
│   Complete some tasks to see your       │
│   accomplishments here.                 │
│                                         │
└─────────────────────────────────────────┘
```

**Stacks Empty State (per segment):**
- In Progress: "No active stacks. Tap + to create one."
- Drafts: "No drafts. Start a stack and save it as a draft."
- Completed: "No completed stacks yet. Keep going!"

---

## 5. Decisions Made

| Question | Decision | Rationale |
|----------|----------|-----------|
| Stack sorting | Creation date (newest first) | Simpler than manual ordering; matches user's mental model of recency |
| Drag-to-reorder | Remove entirely | Not useful in practice; adds complexity without benefit |
| Segment control style | Native `.segmented` picker | Platform-consistent, accessible, familiar |
| Activity MVP scope | Raw event list | Quick to implement; validates the concept before investing in LLM |
| Event types in feed | Completions and activations only | Most meaningful accomplishment signals; avoids noise |
| Third tab | Keep Add button as tab | Maintains discoverability; Gallery can come later |
| LLM summarization | Defer to future phase | Requires more research on Apple's on-device capabilities and cross-platform strategy |

---

## 6. Open Questions

| # | Question | Options | Recommendation |
|---|----------|---------|----------------|
| 1 | Gallery tab now or later? | Show placeholder vs. hide entirely vs. coming soon | Hide for MVP; add when Gallery feature is ready |
| 2 | Activity event types | Just completions vs. completions + activations vs. all events | Completions + activations (meaningful activity) |
| 3 | Activity time range | 7 days vs. 30 days vs. infinite scroll | 30 days with infinite scroll; performance test |
| 4 | Days with no activity | Skip vs. show empty card | Skip days with no activity |
| 5 | Tap activity to navigate | Navigate to Stack/Task vs. just show info | Navigate to Stack/Task if it exists |
| 6 | Activity badge count | Show count of today's completions on tab | No badge for MVP; reconsider later |

---

## 7. Success Metrics

- Users can navigate between stack states without confusion
- Activity feed loads quickly (<500ms for 30 days of events)
- Segment switching is instant (no visible loading)
- No regression in core stack management workflows
- Tab bar feels less cluttered

---

## 8. Implementation Phases

### Phase 1: Stacks Tab Consolidation

**Files to modify:**
- `MainTabView.swift` - Update tab structure
- Create `StacksView.swift` - New unified view with segment control
- Create `InProgressStacksListView.swift` - Extract from HomeView
- Create `DraftsStacksListView.swift` - Extract from DraftsView
- Create `CompletedStacksListView.swift` - Extract from CompletedStacksView
- Update queries to use `createdAt` sorting

**Files to deprecate/remove:**
- `HomeView.swift` - Functionality moves to StacksView
- `DraftsView.swift` - Functionality moves to StacksView
- `CompletedStacksView.swift` - Functionality moves to StacksView

**Remove features:**
- Remove `moveStacks(from:to:)` and `.onMove` modifier
- Remove `StackService.updateSortOrders()` calls for reordering
- Keep `sortOrder` field in model (no migration), just stop using it

### Phase 2: Activity Feed (MVP/Crawl)

**Files to create:**
- `ActivityFeedView.swift` - Main activity view
- `ActivityRowView.swift` - Individual event row
- `ActivityEmptyView.swift` - Empty state

**Implementation:**
- Query `Event` model for relevant event types
- Group by day
- Display in sectioned list
- Tap to navigate to source entity (if exists)

### Phase 3: Polish & Platform Parity

- Test on iOS, iPadOS, macOS
- Ensure segment control works well on all platforms
- Handle dark mode, Dynamic Type
- Add accessibility labels
- Animation polish for segment transitions

### Phase 4 (Future): Activity Feed Walk Phase

- Backend endpoint for daily summaries
- Nightly job to compute summaries
- Client caching of summaries
- Weekly rollup cards

### Phase 5 (Future): Activity Feed Run Phase

- Research Apple Foundation Models framework
- Implement on-device summarization if available
- Backend LLM fallback for cross-platform
- Rich card UI with LLM-generated insights

---

## 9. Dependencies

- Existing `Event` model and event system
- SwiftUI segmented picker (built-in)
- No external dependencies for MVP

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Users miss the segment control | Medium | Use native picker style; clear visual hierarchy |
| Activity query performance with many events | Medium | Limit query to 30 days; lazy loading; pagination if needed |
| Loss of drag-to-reorder frustrates some users | Low | Monitor feedback; creation date sort is predictable |
| macOS segment control differs from iOS | Low | Test thoroughly; use platform-appropriate styling |
| Event payload decoding for activity titles | Medium | Graceful fallback to event type if decode fails |

---

## Appendix A: Event Types Reference

Current event types relevant to Activity Feed:

| Event Type | Meaning | Include in Activity? |
|------------|---------|---------------------|
| `stack.completed` | Stack marked complete | Yes |
| `stack.activated` | Stack became active | Yes |
| `stack.deactivated` | Stack became inactive | No (less meaningful) |
| `task.completed` | Task marked complete | Yes |
| `task.activated` | Task became active focus | Yes |
| `stack.created` | New stack created | Maybe (future) |
| `task.created` | New task created | No (too noisy) |

---

## Appendix B: Migration Notes

### Sort Order Field

The `Stack.sortOrder` field is currently used for manual ordering. After this change:
- Field remains in the model (no schema migration)
- Field is no longer read or written
- Can be removed in a future schema cleanup

### View File Cleanup

After Phase 1, the following files become unused:
- `HomeView.swift` → Delete or keep for reference
- `DraftsView.swift` → Delete
- `CompletedStacksView.swift` → Delete

Consider keeping `HomeView.swift` briefly for reference during implementation, then delete.

---

## Appendix C: Future Considerations

### LLM Summarization Strategy

When implementing the "Run" phase, consider:

1. **Apple Foundation Models (iOS 18.4+)**
   - Check availability of on-device LLM
   - Ideal for privacy and offline capability
   - May have context length limitations

2. **Backend LLM Service**
   - Required for web/Android consistency
   - Can use more capable models
   - Requires sending event data to server

3. **Hybrid Approach**
   - Use on-device when available
   - Fall back to backend for other platforms
   - Backend generates canonical summaries for cross-device consistency

### Attachments & Links Gallery

When implementing the Gallery tab:
- Can reuse the placeholder tab slot
- See `attachments-feature.md` PRD for attachment implementation
- Gallery would show all attachments/links across all stacks
- Consider search/filter capabilities

---

*Last updated: January 2026*
