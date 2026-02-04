# iOS Widgets - PRD

**Feature:** Home Screen & Lock Screen Widgets  
**Author:** Ada (Dequeue Engineer)  
**Date:** 2026-02-03  
**Status:** Draft  
**Related:** ROADMAP.md Section 8

## Problem Statement

Task management apps live and die by widget quality. Users check their active task dozens of times per day - forcing them to open the app each time creates significant friction and hurts engagement.

**Current reality:**
- User working at desk, phone nearby
- Thinks: "What was I working on again?"
- Must: Unlock phone → Find app → Tap app → Wait for launch
- **5-10 seconds of context-switching overhead**

**With widgets:**
- Glance at phone
- See: "🔨 API Integration - Test authentication endpoint"
- **Instant context, zero friction**

This is not a nice-to-have. Widgets are **table stakes** for productivity apps on iOS. Users who can't see their active task at a glance will abandon the app.

## Solution

Native iOS widgets using WidgetKit that display active Stack/Task information on home screen, lock screen, and StandBy mode.

**Key Principles:**
1. **Glanceable**: Readable at a glance, no interaction required
2. **Current**: Always shows what's actually active (synced across devices)
3. **Privacy-aware**: Respect system settings for lock screen visibility
4. **Interactive** (iOS 17+): Quick actions directly from widget
5. **Beautiful**: First-class iOS design, light & dark mode, SF Symbols

## Widget Variants

### 1. Small Widget (2x2 cells)

**Layout:**
```
┌─────────────┐
│ Dequeue     │  ← App name/icon
│             │
│ API Integr..│  ← Active Stack (truncated)
│ 🔨 Test auth │  ← Active Task (with icon)
│             │
└─────────────┘
```

**Content:**
- Active Stack title (1 line, truncated with ...)
- Active Task title (1 line, truncated with ...)
- Visual indicator (⭐ for active)
- Tap → Opens app to Stack detail

**Empty state** (no active Stack):
- "No active Stack"
- Tap → Opens app to Stack list

### 2. Medium Widget (4x2 cells)

**Layout:**
```
┌─────────────────────────────┐
│ Dequeue                      │
│ API Integration          🔨  │
│                              │
│ ✓ Test authentication        │  ← Active Task (checkable, iOS 17+)
│ • Write integration tests    │  ← Next pending
│ • Update documentation       │  ← Next pending
│                              │
└─────────────────────────────┘
```

**Content:**
- Active Stack title
- Active Task (with interactive checkbox iOS 17+)
- Next 2-3 pending tasks in Stack
- Tap task → Opens app to Task detail
- Tap elsewhere → Opens app to Stack detail

**Interactive (iOS 17+):**
- Tap checkbox → Complete active task
- Widget updates immediately
- Next task becomes active

### 3. Lock Screen Widget (Circular)

**iOS 16+ Lock Screen:**
```
┌───────┐
│  API  │  ← Stack title abbreviation (4-6 chars)
│  Intg │
└───────┘
```

**Content:**
- Abbreviated Stack title
- Tap → Opens app

**Privacy:**
- Respects system "Show Previews" setting
- If previews hidden: Shows generic "Active"

### 4. Lock Screen Widget (Rectangular)

**iOS 16+ Lock Screen:**
```
┌─────────────────────────────┐
│ 🔨 API Integration - Test... │
└─────────────────────────────┘
```

**Content:**
- Icon + Active Stack + Active Task (truncated)
- Tap → Opens app

### 5. StandBy Widget (iOS 17+)

**Full-screen display when iPhone is charging in landscape:**
```
┌─────────────────────────────────────┐
│                                     │
│          API Integration            │
│      Test authentication endpoint   │
│                                     │
│      Next: Write integration tests  │
│                                     │
└─────────────────────────────────────┘
```

**Content:**
- Large, readable text for across-the-room viewing
- Active Stack and Task
- Next pending task (preview)
- Minimal UI, high contrast

## Technical Design

### WidgetKit Architecture

**Shared Data via App Groups:**
```swift
// Shared container identifier
let appGroupID = "group.app.dequeue.shared"

// App and Widget both access the same SwiftData ModelContainer
let sharedContainer = try ModelContainer(
    for: Stack.self, Task.self,
    configurations: ModelConfiguration(
        groupContainer: .identifier(appGroupID)
    )
)
```

**Widget Bundle:**
```swift
@main
struct DequeueWidgets: WidgetBundle {
    var body: some Widget {
        SmallWidget()
        MediumWidget()
        LockScreenCircularWidget()
        LockScreenRectangularWidget()
    }
}
```

### Timeline Updates

**Update triggers:**
1. **User activates/completes Stack/Task** → App calls `WidgetCenter.shared.reloadAllTimelines()`
2. **Background sync receives new event** → Reload widgets
3. **Periodic refresh** → Every 15 minutes (iOS decides actual frequency)

**Timeline Provider:**
```swift
struct DequeueWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DequeueWidgetEntry {
        // Static placeholder for gallery view
    }
    
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        // Quick snapshot for widget gallery
        let entry = DequeueWidgetEntry(date: Date(), activeStack: nil, activeTask: nil)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // Fetch current active Stack/Task from shared SwiftData container
        let modelContext = ModelContext(sharedContainer)
        
        let activeStack = try? modelContext.fetch(
            FetchDescriptor<Stack>(predicate: #Predicate { $0.isActive })
        ).first
        
        let activeTask = activeStack?.tasks.first { $0.isActive }
        
        let entry = DequeueWidgetEntry(
            date: Date(),
            activeStack: activeStack,
            activeTask: activeTask,
            pendingTasks: Array(activeStack?.tasks.filter { !$0.isCompleted }.prefix(3) ?? [])
        )
        
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}
```

### Widget Entry Model

```swift
struct DequeueWidgetEntry: TimelineEntry {
    let date: Date
    let activeStack: Stack?
    let activeTask: Task?
    let pendingTasks: [Task]  // For medium widget
    
    var hasActiveWork: Bool {
        activeStack != nil
    }
}
```

### Interactive Widgets (iOS 17+)

**Complete Task Button:**
```swift
Button(intent: CompleteTaskIntent(taskId: task.id.uuidString)) {
    Label("Complete", systemImage: "checkmark.circle")
}
.buttonStyle(.plain)
```

**App Intent:**
```swift
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    
    @Parameter(title: "Task ID")
    var taskId: String
    
    func perform() async throws -> some IntentResult {
        // Access shared ModelContext
        let modelContext = ModelContext(sharedContainer)
        
        // Find task
        guard let uuid = UUID(uuidString: taskId),
              let task = try? modelContext.fetch(
                  FetchDescriptor<Task>(predicate: #Predicate { $0.id == uuid })
              ).first else {
            throw IntentError.taskNotFound
        }
        
        // Complete it via event sourcing
        let eventBus = EventBus(...)
        try await eventBus.recordTaskCompleted(task: task)
        
        // Reload widgets
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result()
    }
}
```

### Privacy Handling

**Lock Screen Visibility:**
```swift
func getEntry() -> DequeueWidgetEntry {
    let entry = ...  // Fetch active Stack/Task
    
    // Check if we're on lock screen and previews are hidden
    if context.isLocked && !UserDefaults(suiteName: appGroupID)!.bool(forKey: "showOnLockScreen") {
        // Return generic entry without sensitive info
        return DequeueWidgetEntry(
            date: Date(),
            activeStack: Stack(title: "Active", ...),  // Generic
            activeTask: nil
        )
    }
    
    return entry
}
```

**User Setting in App:**
```swift
Toggle("Show task details on lock screen", isOn: $showOnLockScreen)
    .onChange(of: showOnLockScreen) {
        UserDefaults(suiteName: appGroupID)!.set($0, forKey: "showOnLockScreen")
        WidgetCenter.shared.reloadAllTimelines()
    }
```

## User Experience

### Adding Widgets

**iOS Standard Flow:**
1. Long-press home screen
2. Tap "+" button
3. Search "Dequeue" or scroll to find
4. Choose widget size
5. Tap "Add Widget"

**In-App Prompt:**
- After completing first Stack, show tip: "Add a widget to see your active task on your home screen"
- Link to Settings → Widgets (if possible)

### Widget States

| State | Display | Behavior |
|-------|---------|----------|
| Active Stack + Task | Show both | Tap → Stack detail |
| Active Stack, no Task | Show Stack, "No active task" | Tap → Stack detail |
| No active Stack | "No active Stack" | Tap → Stack list |
| Loading | Skeleton UI | Non-interactive |
| Error | "Unable to load" | Tap → App |

### Dark Mode & Tinting

**System-provided tinting:**
- Light mode: Dark text on light background
- Dark mode: Light text on dark background
- Tinted mode (iOS 18+): Adapts to user's chosen tint color

**Testing:**
- Test all widgets in Light, Dark, and Tinted modes
- Ensure readability in all contexts
- Verify SF Symbols render correctly

## Acceptance Criteria

### Functional
- [ ] Small widget shows active Stack + Task
- [ ] Medium widget shows active Stack + Task + 2-3 pending tasks
- [ ] Lock screen circular widget shows abbreviated Stack title
- [ ] Lock screen rectangular widget shows Stack + Task (truncated)
- [ ] StandBy widget (iOS 17+) displays large, readable text
- [ ] Tap widget opens app to correct view (Stack detail or list)
- [ ] Widget updates when Stack/Task changes
- [ ] Interactive checkbox (iOS 17+) completes task and updates widget
- [ ] Empty state handled gracefully (no active Stack)
- [ ] Privacy setting hides details on lock screen when enabled

### Design
- [ ] Follows iOS widget design guidelines
- [ ] Readable in light, dark, and tinted modes
- [ ] SF Symbols used consistently
- [ ] Text truncation with ellipsis (no cutoff mid-character)
- [ ] Padding and spacing match iOS standards
- [ ] Widget gallery shows representative placeholder

### Performance
- [ ] Widget loads quickly (<500ms)
- [ ] No excessive battery drain from timeline updates
- [ ] Handles large datasets (1000+ Stacks) without lag

### Privacy
- [ ] Lock screen respects "Show Previews" system setting
- [ ] User can toggle lock screen visibility in app
- [ ] Sensitive task names not visible when locked (if user opts out)

## Edge Cases

1. **No active Stack**: Show "No active Stack", tap opens Stack list
2. **Active Stack, no active Task**: Show Stack name + "No active task"
3. **Very long titles**: Truncate with ellipsis, full text visible in app
4. **Completed active task via widget**: Next task auto-activates, widget updates
5. **Completed active task via app while widget visible**: Widget updates within 15 min or on next explicit reload
6. **Multiple devices**: Widgets on all devices update when any device changes active Stack (via sync)
7. **App not launched recently**: Widget may show stale data until iOS gives it CPU time
8. **App deleted but widget remains**: Widget shows error state
9. **Sync conflict**: Widget shows eventual consistent state (may lag briefly)

## Testing Strategy

### Unit Tests
```swift
@Test func widgetEntryShowsActiveStackAndTask() async throws {
    let stack = Stack(title: "API Integration", isActive: true)
    let task = Task(title: "Test auth", isActive: true)
    stack.tasks.append(task)
    await modelContext.insert(stack)
    
    let entry = await provider.getTimeline(in: context)
    #expect(entry.activeStack?.title == "API Integration")
    #expect(entry.activeTask?.title == "Test auth")
}

@Test func widgetHandlesNoActiveStack() async throws {
    let entry = await provider.getTimeline(in: context)
    #expect(entry.activeStack == nil)
    #expect(entry.hasActiveWork == false)
}

@Test func completeTaskIntentCompletesTask() async throws {
    let task = Task(title: "Test", isActive: true, ...)
    await modelContext.insert(task)
    
    let intent = CompleteTaskIntent(taskId: task.id.uuidString)
    try await intent.perform()
    
    let updated = try await modelContext.fetch(
        FetchDescriptor<Task>(predicate: #Predicate { $0.id == task.id })
    ).first
    #expect(updated?.isCompleted == true)
}
```

### Integration Tests
- Add widget to simulator home screen
- Trigger Stack/Task activation in app
- Verify widget updates
- Complete task via widget, verify app state updates
- Test on real device with lock screen widgets

### Manual Testing
- Test all widget sizes on real device
- Test in Light, Dark, and Tinted modes (iOS 18+)
- Test on lock screen (respecting privacy settings)
- Test in StandBy mode (iOS 17+, charging in landscape)
- Test with very long titles (truncation)
- Test with no active Stack (empty state)
- Test widget gallery appearance

## Implementation Plan

**Estimated: 2-3 days**

### Day 1: Foundation (6-8 hours)
1. Set up App Groups entitlement (30 min)
2. Move ModelContainer to shared container (1 hour)
3. Create Widget Extension target in Xcode (30 min)
4. Implement `TimelineProvider` with basic entry logic (2 hours)
5. Build Small Widget UI (1 hour)
6. Test Small Widget on simulator and device (1 hour)

### Day 2: More Widgets (6-8 hours)
1. Build Medium Widget UI (2 hours)
2. Build Lock Screen widgets (Circular + Rectangular) (2 hours)
3. Build StandBy Widget (iOS 17+) (1 hour)
4. Implement widget reload triggers in app (1 hour)
5. Test all widgets on device (1 hour)

### Day 3: Interactivity & Polish (4-6 hours)
1. Implement `CompleteTaskIntent` for interactive widgets (2 hours)
2. Add privacy setting in app (1 hour)
3. Handle all edge cases (no active Stack, long titles, etc.) (1 hour)
4. Unit tests for timeline provider and intents (1 hour)
5. PR review & merge (1 hour + CI time)

**Total: 16-22 hours** (spread across 3 days with buffer)

## Dependencies

- ✅ SwiftData models already in shared container (or easy to migrate)
- ✅ App Groups entitlement (need to add in Xcode)
- ⚠️ iOS 16+ required for Lock Screen widgets (already our minimum)
- ⚠️ iOS 17+ required for Interactive widgets (graceful degradation for iOS 16)

**No blockers - ready to implement after App Groups setup.**

## Out of Scope

- watchOS widgets (future)
- Custom widget configuration (choose which Stack to display) - Phase 2
- Multiple widgets showing different Stacks - Phase 2
- Widget-specific themes/colors - Phase 2
- Complications for Apple Watch - separate PRD

## Future Enhancements

**Phase 2:**
- Widget configuration: User picks which Stack to show
- Multiple widgets: Different widgets for Work, Personal, etc.
- Custom widget colors/themes
- Task list scrolling in large widget (iOS 17+ API)

**Phase 3:**
- Live Activities for active task timer
- Dynamic Island integration for task switching
- Home screen quick actions from widgets

**Phase 4:**
- Apple Watch complications and widgets
- macOS widgets (if/when supported)
- iPad Lock Screen widgets (when available)

## Success Metrics

**Adoption:**
- % of users who add at least one widget
- % of users who add a lock screen widget
- Average number of widgets per user

**Engagement:**
- Widget impression views per user per day
- Widget tap-through rate
- Interactive widget action rate (task completion via widget)

**Retention:**
- Retention lift for users with widgets vs without

**Target:**
- 40%+ of users add a widget within first week
- 60%+ of widget taps result in app open
- 20%+ of task completions happen via interactive widget (iOS 17+)

---

**Next Steps:**
1. Review PRD with Victor
2. Create implementation ticket (DEQ-XXX)
3. Set up App Groups in Xcode project
4. Implement when CI is responsive
5. Ship and monitor adoption

Widgets are a **table-stakes feature** for productivity apps. Let's make them beautiful and functional. 🚀
