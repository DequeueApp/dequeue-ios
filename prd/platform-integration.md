# Platform Integration (Siri, Shortcuts, Share Extension) - PRD

**Feature:** iOS Platform Integration  
**Author:** Ada (Dequeue Engineer)  
**Date:** 2026-02-03  
**Status:** Draft  
**Related:** ROADMAP.md Section 10

## Problem Statement

Modern iOS users expect seamless integration with platform features. Dequeue currently operates in isolation - users cannot:
- Ask Siri "What's my active task?"
- Add a task using voice commands while driving
- Capture URLs/notes from Safari directly into Dequeue
- Automate workflows with Shortcuts ("When I leave work, activate Personal stack")
- Long-press app icon for quick actions

This creates friction and limits power user adoption. **Users who can't integrate their task manager into their existing workflows will abandon it.**

**Competitor benchmark:**
- Things 3: Excellent Siri support, share extension, Shortcuts
- OmniFocus: Full Shortcuts integration, Siri, share extension
- Todoist: Voice input, share extension, automation

If Dequeue doesn't match these, we lose credibility as a serious productivity tool.

## Solution

Native iOS platform integration using modern APIs:
1. **App Intents** (iOS 16+) for Siri and Shortcuts
2. **Share Extension** for capturing content from other apps
3. **Home Screen Quick Actions** (3D Touch / Long Press)

**Key Principles:**
1. **Voice-first**: Common actions work via Siri with no screen interaction
2. **Automation-friendly**: All core actions available in Shortcuts app
3. **Capture-anywhere**: Share sheet works from Safari, Notes, Messages, etc.
4. **Fast & reliable**: Actions complete instantly, work offline when possible

## Features

### 1. Siri & App Intents

#### Voice Commands (Priority Order)

**Tier 1 (MVP):**
| Command | Response | Action |
|---------|----------|--------|
| "What's my active task?" | Speaks: "Your active task is 'Test authentication endpoint' in API Integration" | Query active Stack + Task |
| "Complete my current task" | Speaks: "Done. Your next task is 'Write tests'" | Mark active task complete, activate next |
| "What am I working on?" | Speaks: "You're working on API Integration" | Query active Stack |

**Tier 2 (Post-MVP):**
| Command | Response | Action |
|---------|----------|--------|
| "Add task [title] to [stack]" | Confirms: "Added 'Buy milk' to Errands" | Create task in specified stack |
| "Switch to [stack]" | Confirms: "Switched to Work" | Activate specified stack |
| "Show my tasks" | Opens app to Stack detail | Navigate to active Stack |
| "Start working" | Confirms: "Work mode started. Active: [stack]" | Enable work mode, prompt for Stack if needed |
| "Stop working" | Confirms: "Work paused. Good job today!" | Disable work mode, deactivate Stack |

**Tier 3 (Future):**
- "Mark [task] as blocked"
- "What did I complete today?"
- "How many tasks do I have in [stack]?"
- "Create a new stack called [name]"

#### Disambiguation

When user intent is ambiguous:
- **Multiple stacks with similar names**: "Which one? Work Project or Side Project?"
- **No active Stack for "complete task"**: "You don't have an active task. Which stack do you want to work on?"
- **Stack name not found**: "I couldn't find a stack called 'Foo'. Did you mean 'Bar'?"

#### Siri Shortcuts App

All App Intents automatically appear in the Shortcuts app as actions. Users can build complex automations:

**Example Automation:**
```
When: I leave "Office" location
Then:
  1. Dequeue: Switch to "Personal" stack
  2. Send message to spouse: "Heading home"
  3. Start podcast playback
```

**Example Shortcut:**
```
Morning Routine:
  1. Dequeue: Start working
  2. Open "Work" stack
  3. Speak: "Your first task is: [active task]"
```

### 2. Share Extension

Capture content from any app into Dequeue via the system share sheet.

#### Supported Content Types

| Content Type | How It's Captured | Example Source App |
|--------------|-------------------|-------------------|
| URL | Creates Task with title = page title, URL stored as attachment/link | Safari, Chrome |
| Text | Creates Task with text as title or description | Notes, Mail |
| Image | Creates Task with image as attachment | Photos, Screenshots |
| File | Creates Task with file as attachment | Files, Dropbox |
| PDF | Creates Task with PDF as attachment | Mail, Files |

#### UI Flow

1. User taps Share button in Safari (viewing a recipe)
2. Scrolls to "Add to Dequeue"
3. Share sheet UI appears:
   - **Task Title** (pre-filled: "Best Chocolate Chip Cookies")
   - **Add to Stack**: Picker showing all Stacks (default: Active Stack)
   - **Create New Stack**: Option to create + add in one step
   - **Add as Task Description**: Toggle (for long text)
   - **Save** / **Cancel**
4. User picks "Recipes" stack
5. Confirmation: "Added to Recipes"
6. Share sheet dismisses

#### Share Extension UI

**Design:**
- Compact, iOS-native design
- Fast (<1 sec to display)
- Works offline (queues for sync if needed)
- Shows recent Stacks for quick picking
- Search bar for finding Stack by name
- "Create New Stack" button at bottom

#### Technical Considerations

- Share extension runs in separate process
- Must access shared SwiftData container (App Groups)
- Limited memory/CPU - keep UI lightweight
- Network may not be available - queue events locally
- Handle all edge cases gracefully (no crashes)

### 3. Home Screen Quick Actions

Long-press app icon → Quick action menu:

**Actions:**
1. **New Stack** → Opens app with new Stack creation sheet
2. **New Task in Active Stack** → Opens app with new Task creation sheet (in active Stack)
3. **View Active Task** → Opens app to active Stack detail view
4. **Complete Active Task** → Completes task, shows confirmation

**Implementation:**
```swift
// In application(_:configurationForConnecting:options:)
UIApplication.shared.shortcutItems = [
    UIApplicationShortcutItem(
        type: "newStack",
        localizedTitle: "New Stack",
        localizedSubtitle: nil,
        icon: UIApplicationShortcutIcon(systemImageName: "tray.full")
    ),
    UIApplicationShortcutItem(
        type: "newTask",
        localizedTitle: "New Task",
        localizedSubtitle: nil,
        icon: UIApplicationShortcutIcon(systemImageName: "plus.circle")
    ),
    UIApplicationShortcutItem(
        type: "viewActive",
        localizedTitle: "View Active Task",
        localizedSubtitle: activeTaskTitle,  // Dynamic
        icon: UIApplicationShortcutIcon(systemImageName: "star")
    ),
    UIApplicationShortcutItem(
        type: "completeActive",
        localizedTitle: "Complete Active Task",
        localizedSubtitle: activeTaskTitle,  // Dynamic
        icon: UIApplicationShortcutIcon(systemImageName: "checkmark.circle")
    )
]
```

**Dynamic Shortcuts:**
- "View Active Task" and "Complete Active Task" update based on what's actually active
- Subtitle shows current task name
- Update when Stack/Task changes

## Technical Design

### App Intents (iOS 16+)

**Framework:** `AppIntents` (modern replacement for SiriKit)

#### 1. Query Active Task Intent

```swift
struct GetActiveTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Active Task"
    static var description = IntentDescription("Get your currently active task")
    
    static var openAppWhenRun: Bool = false  // No need to open app
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Access shared ModelContext
        let modelContext = ModelContext(sharedContainer)
        
        let activeStack = try? modelContext.fetch(
            FetchDescriptor<Stack>(predicate: #Predicate { $0.isActive })
        ).first
        
        let activeTask = activeStack?.tasks.first { $0.isActive }
        
        guard let stack = activeStack else {
            return .result(dialog: "You don't have an active stack right now.")
        }
        
        guard let task = activeTask else {
            return .result(dialog: "You're working on \(stack.title), but no specific task is active.")
        }
        
        return .result(
            dialog: "Your active task is '\(task.title)' in \(stack.title)"
        )
    }
}
```

#### 2. Complete Active Task Intent

```swift
struct CompleteActiveTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Active Task"
    static var description = IntentDescription("Mark your active task as complete")
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let modelContext = ModelContext(sharedContainer)
        
        // Find active task
        let activeStack = try? modelContext.fetch(
            FetchDescriptor<Stack>(predicate: #Predicate { $0.isActive })
        ).first
        
        guard let task = activeStack?.tasks.first(where: { $0.isActive }) else {
            return .result(dialog: "You don't have an active task to complete.")
        }
        
        let taskTitle = task.title
        
        // Complete via event sourcing
        let eventBus = EventBus(...)
        try await eventBus.recordTaskCompleted(task: task)
        
        // Check if there's a next task
        let nextTask = activeStack?.tasks.first { !$0.isCompleted && !$0.isActive }
        
        if let next = nextTask {
            return .result(dialog: "Done. Your next task is '\(next.title)'")
        } else {
            return .result(dialog: "Done. You've completed all tasks in this stack!")
        }
    }
}
```

#### 3. Switch Stack Intent

```swift
struct SwitchStackIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch to Stack"
    static var description = IntentDescription("Activate a different stack")
    
    @Parameter(title: "Stack", description: "The stack to switch to")
    var stack: StackEntity
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Deactivate current active Stack
        // Activate the specified Stack
        // Return confirmation
        
        return .result(dialog: "Switched to \(stack.title)")
    }
}
```

#### 4. App Shortcuts Provider

```swift
struct DequeueAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetActiveTaskIntent(),
            phrases: [
                "What's my active task in \(.applicationName)?",
                "What am I working on in \(.applicationName)?",
                "Show my current task in \(.applicationName)"
            ],
            shortTitle: "Get Active Task",
            systemImageName: "star"
        )
        
        AppShortcut(
            intent: CompleteActiveTaskIntent(),
            phrases: [
                "Complete my current task in \(.applicationName)",
                "Mark my task done in \(.applicationName)",
                "Finish my active task in \(.applicationName)"
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle"
        )
        
        // More shortcuts...
    }
}
```

### Share Extension

**Target:** iOS App Extension (Share Extension)

**Architecture:**
- Separate process from main app
- Shared SwiftData container via App Groups
- Lightweight UI (< 10 MB memory)
- Event-driven: User shares → Extension writes event → App syncs

**Files:**
```
ShareExtension/
  ShareViewController.swift       ← Entry point
  ShareView.swift                ← SwiftUI picker UI
  ShareViewModel.swift           ← Logic
  Info.plist                     ← Accepted content types
```

**Info.plist configuration:**
```xml
<key>NSExtensionActivationRule</key>
<dict>
    <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
    <integer>1</integer>
    <key>NSExtensionActivationSupportsText</key>
    <true/>
    <key>NSExtensionActivationSupportsImageWithMaxCount</key>
    <integer>5</integer>
    <key>NSExtensionActivationSupportsFileWithMaxCount</key>
    <integer>5</integer>
</dict>
```

**ShareViewController:**
```swift
class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Extract shared content
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            cancel()
            return
        }
        
        // Process attachments (URL, text, image, file)
        processAttachments(attachments) { result in
            // Show SwiftUI picker UI
            let shareView = ShareView(sharedContent: result)
            let hostingController = UIHostingController(rootView: shareView)
            self.addChild(hostingController)
            self.view.addSubview(hostingController.view)
            // Layout constraints...
        }
    }
    
    func done(stack: Stack, taskTitle: String, attachment: Data?) {
        // Write event to shared container
        let modelContext = ModelContext(sharedContainer)
        let eventBus = EventBus(modelContext: modelContext)
        
        try? await eventBus.recordTaskCreated(
            stack: stack,
            title: taskTitle,
            attachment: attachment
        )
        
        // Notify main app to sync
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("app.dequeue.shareextension.newcontent" as CFString),
            nil, nil, true
        )
        
        // Dismiss
        extensionContext?.completeRequest(returningItems: nil)
    }
    
    func cancel() {
        extensionContext?.cancelRequest(withError: NSError(...))
    }
}
```

### Entity Resolution (for Siri)

When user says "Switch to Work stack", Siri needs to resolve "Work stack" to an actual Stack entity.

**StackEntity (App Entity):**
```swift
struct StackEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Stack")
    static var defaultQuery = StackEntityQuery()
    
    var id: UUID
    var title: String
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct StackEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [StackEntity] {
        // Fetch Stacks by UUIDs
    }
    
    func suggestedEntities() async throws -> [StackEntity] {
        // Return all Stacks for autocomplete
    }
    
    func entities(matching string: String) async throws -> [StackEntity] {
        // Fuzzy search for Stack by name
        let modelContext = ModelContext(sharedContainer)
        let stacks = try modelContext.fetch(
            FetchDescriptor<Stack>(
                predicate: #Predicate { 
                    $0.title.localizedStandardContains(string) 
                }
            )
        )
        return stacks.map { StackEntity(id: $0.id, title: $0.title) }
    }
}
```

## Acceptance Criteria

### Siri & App Intents
- [ ] "What's my active task?" works via Siri
- [ ] "Complete my current task" works via Siri
- [ ] "What am I working on?" works via Siri
- [ ] Intents work without opening the app (when possible)
- [ ] Intents appear in Shortcuts app as actions
- [ ] Disambiguation works for ambiguous stack names
- [ ] Graceful error messages for edge cases (no active task, etc.)
- [ ] Works offline for query intents (read-only)

### Share Extension
- [ ] "Add to Dequeue" appears in share sheet
- [ ] Works from Safari (URL capture)
- [ ] Works from Notes (text capture)
- [ ] Works from Photos (image capture)
- [ ] Works from Files (file capture)
- [ ] UI loads in <1 second
- [ ] Can create new Stack from share extension
- [ ] Can pick existing Stack (with search)
- [ ] Works offline (queues event for sync)
- [ ] No crashes or hangs

### Quick Actions
- [ ] Long-press app icon shows quick actions
- [ ] "New Stack" opens app with creation sheet
- [ ] "New Task" opens app with task creation (in active Stack)
- [ ] "View Active Task" navigates to Stack detail
- [ ] "Complete Active Task" completes task without opening app (or opens briefly)
- [ ] Dynamic actions update based on active Stack/Task

### Design
- [ ] Share extension UI matches app design
- [ ] Siri responses are natural and helpful
- [ ] Error messages are friendly and actionable
- [ ] Share extension respects Dark Mode
- [ ] Quick action icons clear and consistent with app

## Edge Cases

1. **No active Stack for "complete task"**: Respond "You don't have an active task. Want to activate a stack?"
2. **Multiple Stacks with same name**: Disambiguate: "Which 'Work' stack? Work Projects or Side Work?"
3. **Share extension while offline**: Queue event, show "Saved. Will sync when online"
4. **Share extension memory limit exceeded**: Graceful error, don't crash
5. **Siri on locked device**: May require unlock for sensitive intents (user-configurable)
6. **Stack name not found**: "I couldn't find a stack called 'Foo'. Did you mean 'Bar'?"
7. **Quick action for "Complete Active Task" when no active task**: Open app with message

## Testing Strategy

### Unit Tests
```swift
@Test func getActiveTaskIntentReturnsCorrectTask() async throws {
    let stack = Stack(title: "Work", isActive: true)
    let task = Task(title: "Test", isActive: true)
    stack.tasks.append(task)
    await modelContext.insert(stack)
    
    let intent = GetActiveTaskIntent()
    let result = try await intent.perform()
    
    #expect(result.dialog.contains("Test"))
    #expect(result.dialog.contains("Work"))
}

@Test func completeActiveTaskIntentCompletesTask() async throws {
    let stack = Stack(title: "Work", isActive: true)
    let task = Task(title: "Test", isActive: true)
    stack.tasks.append(task)
    await modelContext.insert(stack)
    
    let intent = CompleteActiveTaskIntent()
    try await intent.perform()
    
    let updated = try await modelContext.fetch(
        FetchDescriptor<Task>(predicate: #Predicate { $0.id == task.id })
    ).first
    #expect(updated?.isCompleted == true)
}
```

### Integration Tests
- Test each Siri phrase manually on device
- Test Shortcuts automations (location-based, time-based)
- Test share extension from multiple apps (Safari, Notes, Photos)
- Test quick actions from home screen
- Test offline behavior (share extension queues events)

### Manual Testing
- Ask Siri all supported queries
- Build a Shortcut automation and test it
- Share URLs, text, images from various apps
- Test on device, not simulator (Siri doesn't work in simulator)
- Test with multiple user languages (if supported)

## Implementation Plan

**Estimated: 3-4 days**

### Day 1: App Intents (6-8 hours)
1. Define `GetActiveTaskIntent` (1 hour)
2. Define `CompleteActiveTaskIntent` (1 hour)
3. Define `StackEntity` and `StackEntityQuery` (2 hours)
4. Define `AppShortcutsProvider` with phrases (1 hour)
5. Test on device with Siri (1 hour)
6. Handle edge cases and errors (1 hour)

### Day 2: Share Extension (6-8 hours)
1. Create Share Extension target in Xcode (30 min)
2. Implement `ShareViewController` (2 hours)
3. Build SwiftUI picker UI (2 hours)
4. Handle URL, text, image attachments (1 hour)
5. Test from Safari, Notes, Photos (1 hour)
6. Handle offline/error cases (30 min)

### Day 3: Quick Actions (4-6 hours)
1. Implement dynamic UIApplicationShortcutItems (1 hour)
2. Handle quick action routing in app delegate (1 hour)
3. Test all four quick actions (1 hour)
4. Unit tests for intents (2 hours)

### Day 4: Polish & Testing (4-6 hours)
1. Integration tests (2 hours)
2. Manual testing on device (2 hours)
3. Documentation (1 hour)
4. PR review & merge (1 hour + CI time)

**Total: 20-28 hours** (spread across 4 days)

## Dependencies

- ✅ iOS 16+ (App Intents framework)
- ✅ App Groups entitlement (for Share Extension)
- ✅ Siri entitlement (request in Xcode)
- ⚠️ Real device required for Siri testing (simulator unsupported)

**No blockers - ready to implement after App Groups + Siri entitlements setup.**

## Out of Scope

- Android platform integration (separate PRD)
- macOS-specific integrations (Finder sync, menu bar app)
- watchOS complications (separate PRD)
- Third-party automation tools (Zapier, IFTTT) - Phase 2

## Future Enhancements

**Phase 2:**
- More Siri intents: "Create stack", "Mark as blocked", "What did I complete today?"
- Natural language parsing: "Add buy milk to my shopping stack tomorrow at 3pm"
- Context awareness: "Continue where I left off" (activate last active Stack)
- Multi-language support for Siri phrases

**Phase 3:**
- Apple Watch app with Siri support
- CarPlay integration for voice capture while driving
- Handoff support (start on iPhone, continue on Mac)
- Spotlight search integration (search Stacks/Tasks from system search)

## Success Metrics

**Adoption:**
- % of users who trigger at least one Siri intent
- % of users who use share extension
- % of users who use quick actions

**Engagement:**
- Siri intent invocations per user per day
- Share extension uses per user per week
- Quick action taps per user per week

**Retention:**
- Retention lift for users who use Siri vs those who don't
- Retention lift for users who use share extension

**Target:**
- 20%+ of users try Siri integration within first month
- 30%+ of users try share extension within first month
- 50%+ of users who try Siri/share continue using it weekly

---

**Next Steps:**
1. Review PRD with Victor
2. Create implementation ticket (DEQ-XXX)
3. Request Siri entitlement in Xcode
4. Implement when CI is responsive
5. Ship and monitor adoption

Platform integration is **essential** for competing with established task managers. Let's make Dequeue a first-class iOS citizen. 🚀
