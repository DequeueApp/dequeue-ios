# Performance Issues Analysis

> **Note:** This document is now historical. All outstanding performance issues have been migrated to Linear (DEQ-140 through DEQ-146). Linear is the single source of truth for active work items.

This document catalogs performance issues identified in the dequeue-ios codebase, prioritized by impact and difficulty to fix.

---

## Critical Issues

### 1. Sync Delays - No Immediate Push on Event Creation

**Location:** `Dequeue/Dequeue/Sync/SyncManager.swift:694-725`

**Problem:** When a user creates/updates/deletes data, events are recorded locally but NOT immediately pushed to the server. The sync only happens via periodic polling every 10 seconds. This is why events appear as "pending" in the Event Log - they're waiting for the next sync cycle.

**Current Flow:**
```
User Action → Event Created (isSynced=false) → Wait up to 10 seconds → Periodic Sync → Push to Server
```

**Expected Flow:**
```
User Action → Event Created → Immediate Push via WebSocket or HTTP → Mark Synced
```

**Code:**
```swift
// SyncManager.swift:709-724
periodicSyncTask = Task { [weak self] in
    while let self = self, await self.isConnected {
        try? await Task.sleep(for: .seconds(10))  // ⚠️ 10 second delay!

        guard await self.isConnected else { break }

        do {
            try await self.pushEvents()  // Only pushes here
            try await self.pullEvents()
        } catch { ... }
    }
}
```

**Impact:** High - Users see "pending" events for up to 10 seconds, feels slow/broken

**Fix:** Add immediate push trigger after any event is recorded. Either:
- Option A: Expose a `triggerPush()` method that EventService calls after recording
- Option B: Use NotificationCenter/Combine to signal new events
- Option C: Push events over WebSocket instead of HTTP POST

---

### 2. Sync Delays - WebSocket is Receive-Only

**Location:** `Dequeue/Dequeue/Sync/SyncManager.swift:601-624`

**Problem:** The WebSocket connection is only used to RECEIVE events from the server. Outgoing events are pushed via HTTP POST (`/sync/push`), which requires waiting for the periodic sync.

**Current Architecture:**
```
WebSocket: Server → Client (receive only)
HTTP POST: Client → Server (batched, periodic)
```

**Optimal Architecture:**
```
WebSocket: Bidirectional (immediate send/receive)
```

**Impact:** High - Fundamental architectural issue causing sync delays

**Fix:** Modify `pushEvents()` to optionally send via WebSocket when connected, falling back to HTTP when disconnected.

---

### 3. Add Stack Stuttering - Multiple Database Saves Per Operation

**Location:** `Dequeue/Dequeue/Services/EventService.swift:279-280`

**Problem:** Every call to `recordEvent()` triggers a `modelContext.save()`. A single stack creation can trigger 2-3 saves:

```swift
// StackService.createStack() triggers:
1. eventService.recordStackCreated(stack)  → save()
2. eventService.recordStackActivated(stack) → save() (if first stack)
3. try modelContext.save()                  → save()
```

This means 2-3 disk I/O operations blocking the main thread for a single user action.

**Code:**
```swift
// EventService.swift:276-281
private func recordEvent<T: Encodable>(type: EventType, payload: T, entityId: String? = nil) throws {
    let payloadData = try JSONEncoder().encode(payload)
    let event = Event(eventType: type, payload: payloadData, entityId: entityId)
    modelContext.insert(event)
    try modelContext.save()  // ⚠️ Save on EVERY event!
}
```

**Impact:** High - UI stutters on every data modification

**Fix:** Remove `modelContext.save()` from `recordEvent()`. Let the calling service batch saves:
```swift
// Instead of saving in recordEvent, save once in the service:
try eventService.recordStackCreated(stack)
try eventService.recordStackActivated(stack)
try modelContext.save()  // Single save for all changes
```

---

### 4. Add Stack Stuttering - All Services @MainActor

**Location:**
- `Dequeue/Dequeue/Services/StackService.swift:59`
- `Dequeue/Dequeue/Services/EventService.swift:14`
- `Dequeue/Dequeue/Services/TaskService.swift` (similar)

**Problem:** Services are marked `@MainActor`, meaning ALL database operations (queries, inserts, saves) run on the main thread. This blocks UI rendering during:
- Database queries (`try modelContext.fetch()`)
- JSON encoding (`JSONEncoder().encode()`)
- Disk writes (`modelContext.save()`)

**Code:**
```swift
@MainActor
final class StackService { ... }

@MainActor
final class EventService { ... }
```

**Impact:** High - Main thread blocked during all data operations

**Fix:** Consider:
1. Moving heavy operations to background context
2. Using `Task.detached` for CPU-intensive JSON encoding
3. Creating a background ModelContext for batch operations

---

## High Priority Issues

### 5. Regex Parsing on Every Incoming Event

**Location:** `Dequeue/Dequeue/Sync/SyncManager.swift:79-99`

**Problem:** The timestamp parsing uses `NSRegularExpression` which is expensive. This regex is compiled and executed for EVERY incoming event during sync.

**Code:**
```swift
private static func truncateNanosecondsToMilliseconds(_ string: String) -> String {
    let pattern = #"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.(\d{3})\d*(Z|[+-]\d{2}:\d{2})"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {  // ⚠️ Compiled every call
        return string
    }
    // ...
}
```

**Impact:** Medium-High - Slow sync when processing many events

**Fix:** Pre-compile the regex as a static property:
```swift
private static let nanosecondsRegex = try! NSRegularExpression(
    pattern: #"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.(\d{3})\d*(Z|[+-]\d{2}:\d{2})"#
)
```

---

### 6. HomeView Runs 4 Separate Queries on Init

**Location:** `Dequeue/Dequeue/Views/Home/HomeView.swift:13-52`

**Problem:** HomeView initializes 4 separate `@Query` properties, each triggering a database query:

```swift
@Query private var stacks: [Stack]      // Query 1: active stacks
@Query private var allStacks: [Stack]   // Query 2: all stacks
@Query private var tasks: [QueueTask]   // Query 3: all tasks
@Query private var reminders: [Reminder] // Query 4: all reminders
```

**Impact:** Medium - Slower view initialization, especially with large datasets

**Fix:** Consider:
1. Lazy loading `allStacks` and `tasks` only when needed (reminder navigation)
2. Using a single query with computed filters
3. Moving reminder badge calculation to a background task

---

### 7. ProjectorService N+1 Query Problem

**Location:** `Dequeue/Dequeue/Sync/ProjectorService.swift:495-511`

**Problem:** When processing N events from sync, each event triggers individual database lookups:

```swift
private static func findStack(id: String, context: ModelContext) throws -> Stack? {
    let predicate = #Predicate<Stack> { $0.id == id }
    let descriptor = FetchDescriptor<Stack>(predicate: predicate)
    return try context.fetch(descriptor).first  // ⚠️ Query per event
}
```

For 100 events, this means 100+ database queries.

**Impact:** Medium-High - Slow sync with many events

**Fix:** Batch prefetch entities before processing:
```swift
// Collect all IDs first
let stackIds = events.compactMap { extractStackId($0) }
// Single query to fetch all
let stacks = try fetchStacks(ids: stackIds, context: context)
let stackMap = Dictionary(uniqueKeysWithValues: stacks.map { ($0.id, $0) })
// Process using map lookup
```

---

## Medium Priority Issues

### 8. HomeView moveStacks Missing Event Recording

**Location:** `Dequeue/Dequeue/Views/Home/HomeView.swift:157-166`

**Problem:** When user drags to reorder stacks, the sort orders are updated but:
1. No `stack.reordered` event is recorded
2. No `modelContext.save()` is called
3. Changes may not persist or sync

**Code:**
```swift
private func moveStacks(from source: IndexSet, to destination: Int) {
    var reorderedStacks = stacks
    reorderedStacks.move(fromOffsets: source, toOffset: destination)

    for (index, stack) in reorderedStacks.enumerated() {
        stack.sortOrder = index
        stack.updatedAt = Date()
        stack.syncState = .pending
    }
    // ⚠️ Missing: eventService.recordStackReordered()
    // ⚠️ Missing: modelContext.save()
}
```

**Impact:** Medium - Reorder changes may not persist/sync

**Fix:** Add event recording and save:
```swift
let stackService = StackService(modelContext: modelContext)
try stackService.updateSortOrders(reorderedStacks)
```

---

### 9. DeviceService.getDeviceId Called Every Push

**Location:** `Dequeue/Dequeue/Sync/SyncManager.swift:244`

**Problem:** Every push operation calls `await DeviceService.shared.getDeviceId()`. While this is cached, it still requires an actor hop.

**Code:**
```swift
func pushEvents() async throws {
    // ...
    let deviceId = await DeviceService.shared.getDeviceId()  // ⚠️ Actor hop every push
    // ...
}
```

**Impact:** Low-Medium - Minor overhead per push

**Fix:** Cache deviceId at connection time:
```swift
private var cachedDeviceId: String?

func connect(...) async throws {
    self.cachedDeviceId = await DeviceService.shared.getDeviceId()
    // ...
}
```

---

### 10. Multiple Fetches in setAsActive

**Location:** `Dequeue/Dequeue/Services/StackService.swift:275-289`

**Problem:** `setAsActive()` performs two separate fetch operations:

```swift
let allCurrentlyActiveStacks = try getAllStacksWithIsActiveTrue()  // Query 1
// ...
let activeStacks = try getActiveStacks()  // Query 2
```

**Impact:** Low-Medium - Extra database roundtrip

**Fix:** Combine into single fetch, filter in memory:
```swift
let allNonDeletedStacks = try getAllNonDeletedStacks()
let activeStacks = allNonDeletedStacks.filter { $0.isActive && $0.status == .active }
```

---

## Low Priority Issues

### 11. Event History Fetches All Events Then Filters

**Location:** `Dequeue/Dequeue/Services/EventService.swift:262-272`

**Problem:** `fetchStackHistoryWithRelated` fetches ALL events, then filters in memory:

```swift
let descriptor = FetchDescriptor<Event>(
    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
)
let allEvents = try modelContext.fetch(descriptor)  // ⚠️ Fetches ALL events

return allEvents.filter { event in
    guard let eventEntityId = event.entityId else { return false }
    return entityIds.contains(eventEntityId)
}
```

**Impact:** Low - Only affects Event History view, scales poorly with event count

**Fix:** Use IN predicate (may require workaround for SwiftData limitations)

---

### 12. New ISO8601DateFormatter Created Per Push

**Location:** `Dequeue/Dequeue/Sync/SyncManager.swift:256`

**Problem:** Creates a new `ISO8601DateFormatter()` for each event in the push:

```swift
let syncEvents = pendingEvents.map { event -> [String: Any] in
    // ...
    return [
        // ...
        "ts": ISO8601DateFormatter().string(from: event.timestamp),  // ⚠️ New formatter each time
        // ...
    ]
}
```

**Impact:** Low - Minor allocation overhead

**Fix:** Reuse the existing static formatters:
```swift
"ts": SyncManager.iso8601WithFractionalSeconds.string(from: event.timestamp)
```

---

### 13. onChange Triggers Database Operation During Typing

**Location:** `Dequeue/Dequeue/Views/Stack/StackEditorView+CreateMode.swift:24-29`

**Problem:** The `onChange(of: title)` handler triggers draft creation on the FIRST keystroke:

```swift
.onChange(of: title) { _, newValue in
    if draftStack == nil && !newValue.isEmpty && !isCreatingDraft {
        createDraft(title: newValue)  // ⚠️ Database ops on first keystroke
    }
}
```

While this only happens once per view, it can cause a noticeable hitch when typing begins.

**Impact:** Low - Only affects first character, but noticeable

**Fix:** Consider debouncing or creating draft on blur/submit instead of first keystroke

---

## Summary Table

| # | Issue | Impact | Difficulty | File:Line | Status | Linear Issue |
|---|-------|--------|------------|-----------|--------|--------------|
| 1 | No immediate push | Critical | Medium | SyncManager.swift:694 | ✅ COMPLETED | N/A |
| 2 | WebSocket receive-only | High | High | SyncManager.swift:601 | 🟡 Open | [DEQ-140](https://linear.app/dequeue/issue/DEQ-140) |
| 3 | Multiple saves per event | Critical | Easy | EventService.swift:280 | ✅ COMPLETED | N/A |
| 4 | Services @MainActor | Critical | Medium | StackService.swift:59 | 🔴 Open | [DEQ-141](https://linear.app/dequeue/issue/DEQ-141) |
| 5 | Regex compiled per event | High | Easy | SyncManager.swift:79 | ✅ COMPLETED | N/A |
| 6 | 4 queries in HomeView | High | Medium | HomeView.swift:13 | 🟡 Open | [DEQ-142](https://linear.app/dequeue/issue/DEQ-142) |
| 7 | N+1 queries in Projector | High | Medium | ProjectorService.swift:495 | 🟡 Open | [DEQ-143](https://linear.app/dequeue/issue/DEQ-143) |
| 8 | moveStacks no save | Medium | Easy | HomeView.swift:157 | ✅ COMPLETED | N/A |
| 9 | DeviceId actor hop | Low-Med | Easy | SyncManager.swift:244 | ✅ COMPLETED | N/A |
| 10 | Multiple fetches setAsActive | Low-Med | Easy | StackService.swift:275 | 🟢 Open | [DEQ-144](https://linear.app/dequeue/issue/DEQ-144) |
| 11 | Event history fetch all | Low | Medium | EventService.swift:262 | ⏳ In PR | [DEQ-145](https://linear.app/dequeue/issue/DEQ-145) → [PR #227](https://github.com/DequeueApp/dequeue-ios/pull/227) |
| 12 | DateFormatter per push | Low | Easy | SyncManager.swift:256 | ✅ COMPLETED | N/A |
| 13 | onChange database call | Low | Easy | StackEditorView+CreateMode.swift:24 | 🟢 Open | [DEQ-146](https://linear.app/dequeue/issue/DEQ-146) |

**Legend:**
- ✅ COMPLETED - Issue has been resolved
- 🔴 Open (Critical) - High priority, needs immediate attention
- 🟡 Open (High) - Important, should be addressed soon
- 🟢 Open (Low/Medium) - Can be addressed later

---

## Recommended Fix Order

### Phase 1: Quick Wins (Easy, High Impact)
1. **Issue #3**: Remove save() from recordEvent() - single line change
2. **Issue #5**: Pre-compile regex patterns - simple refactor
3. **Issue #12**: Reuse date formatters - simple refactor

### Phase 2: Sync Improvements (Medium Effort, Critical Impact)
4. **Issue #1**: Add immediate push trigger after event recording
5. **Issue #9**: Cache deviceId at connection time

### Phase 3: Architecture Improvements (Higher Effort)
6. **Issue #4**: Move heavy operations off main thread
7. **Issue #7**: Batch prefetch in ProjectorService
8. **Issue #2**: Add WebSocket send capability (if server supports)

---

## Fixes Applied in This PR

### Issue #1: Immediate Push
- Added `triggerImmediatePush()` method to SyncManager for services to call after saving
- Reduced periodic sync interval from 10 seconds to 3 seconds as fallback

### Issue #3: Multiple Saves Per Event
- Removed `modelContext.save()` from `EventService.recordEvent()`
- Services now batch saves (single save after all events recorded)

### Issue #5: Regex Compiled Per Event
- Pre-compiled regex patterns as static properties (`nanosecondsRegex`, `fractionalSecondsRegex`)
- Patterns are now compiled once at class load, reused for all timestamp parsing

### Issue #8: moveStacks No Save
- Updated `HomeView.moveStacks()` to use `StackService.updateSortOrders()`
- Updated `HomeView.deleteStacks()` to use `StackService.deleteStack()`
- Both now properly record events and save to database

### Issue #9: DeviceId Actor Hop
- Added `deviceId` property to SyncManager, cached at connection time
- Push operations now use cached deviceId, avoiding actor hop

### Issue #12: DateFormatter Per Push
- Changed `ISO8601DateFormatter().string()` to use pre-existing static formatter
- Now uses `SyncManager.iso8601WithFractionalSeconds`

---

## Related Slack Thread

https://infinitejustice.slack.com/archives/C0A660H030D/p1767479807565069
