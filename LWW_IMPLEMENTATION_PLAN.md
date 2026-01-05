# Last-Write-Wins (LWW) Implementation Plan

> **Implementation Status: ✅ 100% COMPLETE** (2024-12-21)
>
> All LWW conflict resolution features have been successfully implemented.
> This document is now historical and serves as reference for the implementation.

> **Progress Tracker**
> | Phase | Description | Status | Date Completed |
> |-------|-------------|--------|----------------|
> | 1 | Core LWW Fix (ProjectorService) | ✅ Complete | 2024-12-21 |
> | 2 | Add entityId to Event Model | ✅ Complete | 2024-12-21 |
> | 3 | History Query Service | ✅ Complete | 2024-12-21 |
> | 4 | History View UI | ✅ Complete | 2024-12-21 |
> | 5 | Revert Capability | ✅ Complete | 2024-12-21 |

## Overview

Implementation plan for Last-Write-Wins conflict resolution with full event history preservation.

### Design Principles

1. **LWW by Timestamp** - Latest timestamp always wins, no revision counters
2. **Append-Only Events** - Events are immutable, never deleted or modified
3. **Full History** - All events preserved for audit trail and revert capability
4. **Deterministic** - Same events applied in any order produce same final state
5. **Single Actor** - Designed for single user across multiple devices

### Why LWW by Timestamp (Not Revision Numbers)

| Approach | Problem |
|----------|---------|
| Revision OCC | Device A has rev=5, Device B has rev=5, both edit → conflict! |
| LWW Timestamp | Device A edits at 10:00:00.123, Device B at 10:00:05.456 → B wins, deterministic |

With millisecond precision, timestamp collisions are astronomically rare for human-speed single-actor edits.

---

## Implementation Phases

### Phase 1: Core LWW Fix (Critical) ✅

**Status:** Complete (2024-12-21)

**Files to modify:**
- `Dequeue/Sync/ProjectorService.swift`

**Changes:**

Add timestamp guard to all update methods. Only apply events where `event.timestamp > entity.updatedAt`.

```swift
private static func applyStackUpdated(event: Event, context: ModelContext) throws {
    let payload = try event.decodePayload(StackEventPayload.self)
    guard let stack = try findStack(id: payload.id, context: context) else { return }

    // Skip updates to deleted entities
    guard !stack.isDeleted else { return }

    // LWW: Only apply if this event is newer
    guard event.timestamp > stack.updatedAt else { return }

    updateStack(stack, from: payload, eventTimestamp: event.timestamp)
}

private static func updateStack(_ stack: Stack, from payload: StackEventPayload, eventTimestamp: Date) {
    stack.title = payload.title
    stack.stackDescription = payload.description
    stack.status = payload.status
    stack.priority = payload.priority
    stack.sortOrder = payload.sortOrder
    stack.isDraft = payload.isDraft
    stack.updatedAt = eventTimestamp  // ← Use EVENT timestamp, not Date()
    stack.syncState = .synced
    stack.lastSyncedAt = Date()
}
```

**Critical insight:** `entity.updatedAt` must be set to the EVENT's timestamp, not `Date()`. This ensures deterministic state regardless of sync order.

**Methods updated with LWW guards:**
- [x] ✅ `applyStackUpdated`
- [x] ✅ `applyStackDeleted`
- [x] ✅ `applyStackCompleted`
- [x] ✅ `applyStackActivated`
- [x] ✅ `applyStackDeactivated`
- [x] ✅ `applyStackClosed`
- [x] ✅ `applyStackReordered`
- [x] ✅ `applyTaskUpdated`
- [x] ✅ `applyTaskDeleted`
- [x] ✅ `applyTaskCompleted`
- [x] ✅ `applyTaskActivated`
- [x] ✅ `applyTaskClosed`
- [x] ✅ `applyTaskReordered`
- [x] ✅ `applyReminderUpdated`
- [x] ✅ `applyReminderDeleted`
- [x] ✅ `applyReminderSnoozed`

---

### Phase 2: Add entityId to Event Model ✅

**Status:** Complete (2024-12-21)

**Files to modify:**
- `Dequeue/Models/Event.swift`
- `Dequeue/Services/EventService.swift`

**Changes:**

Add indexed `entityId` field for efficient history queries:

```swift
// Event.swift
@Model
final class Event {
    @Attribute(.unique) var id: UUID
    var type: String
    var payload: Data
    var timestamp: Date
    var metadata: Data?
    var entityId: UUID?  // ← ADD THIS

    // Sync tracking
    var isSynced: Bool
    var syncedAt: Date?

    // ... existing code
}
```

Update EventService to populate entityId:

```swift
// EventService.swift
private func recordEvent<T: Encodable>(type: EventType, payload: T, entityId: UUID) throws {
    let payloadData = try JSONEncoder().encode(payload)
    let event = Event(eventType: type, payload: payloadData)
    event.entityId = entityId
    modelContext.insert(event)
    try modelContext.save()
}

func recordStackCreated(_ stack: Stack) throws {
    let payload = StackEventPayload(/* ... */)
    try recordEvent(type: .stackCreated, payload: payload, entityId: stack.id)
}
```

---

### Phase 3: History Query Service ✅

**Status:** Complete (2024-12-21)

**Files to modify:**
- `Dequeue/Services/EventService.swift`

**Changes:**

Add method to fetch all events for an entity:

```swift
func fetchHistory(for entityId: UUID) throws -> [Event] {
    let predicate = #Predicate<Event> { event in
        event.entityId == entityId
    }
    let descriptor = FetchDescriptor<Event>(
        predicate: predicate,
        sortBy: [SortDescriptor(\.timestamp)]  // Chronological order
    )
    return try modelContext.fetch(descriptor)
}

func fetchHistoryReversed(for entityId: UUID) throws -> [Event] {
    let predicate = #Predicate<Event> { event in
        event.entityId == entityId
    }
    let descriptor = FetchDescriptor<Event>(
        predicate: predicate,
        sortBy: [SortDescriptor(\.timestamp, order: .reverse)]  // Most recent first
    )
    return try modelContext.fetch(descriptor)
}
```

---

### Phase 4: History View UI ✅

**Status:** Complete (2024-12-21)

**Files to create:**
- `Dequeue/Views/Stack/StackHistoryView.swift`

**Changes:**

Create history view showing all events for a stack:

```swift
struct StackHistoryView: View {
    let stack: Stack
    @Environment(\.modelContext) private var modelContext
    @State private var events: [Event] = []

    var body: some View {
        List(events) { event in
            StackHistoryRow(event: event)
        }
        .navigationTitle("History")
        .task {
            let service = EventService(modelContext: modelContext)
            events = (try? service.fetchHistoryReversed(for: stack.id)) ?? []
        }
    }
}

struct StackHistoryRow: View {
    let event: Event

    private var actionLabel: String {
        switch event.type {
        case "stack.created": return "Created"
        case "stack.updated": return "Updated"
        case "stack.completed": return "Completed"
        case "stack.deleted": return "Deleted"
        default: return event.type
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(actionLabel)
                    .font(.headline)
                Spacer()
                Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let payload = try? event.decodePayload(StackEventPayload.self) {
                Text(payload.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
```

---

### Phase 5: Revert Capability ✅

**Status:** Complete (2024-12-21)

**Files to modify:**
- `Dequeue/Services/StackService.swift`
- `Dequeue/Views/Stack/StackHistoryView.swift`

**Changes:**

Add revert method (creates NEW event with historical values):

```swift
// StackService.swift
func revertToHistoricalState(_ stack: Stack, from event: Event) throws {
    let historicalPayload = try event.decodePayload(StackEventPayload.self)

    // Apply historical values
    stack.title = historicalPayload.title
    stack.stackDescription = historicalPayload.description
    stack.status = historicalPayload.status
    stack.priority = historicalPayload.priority
    stack.sortOrder = historicalPayload.sortOrder
    stack.isDraft = historicalPayload.isDraft
    stack.updatedAt = Date()  // Current time - this IS a new edit
    stack.syncState = .pending

    // Record as a NEW update event (preserves immutable history)
    try eventService.recordStackUpdated(stack)
    try modelContext.save()
}
```

Add revert action to history view:

```swift
// In StackHistoryRow or StackHistoryView
Button("Revert to this version") {
    let stackService = StackService(modelContext: modelContext)
    try? stackService.revertToHistoricalState(stack, from: event)
}
```

**Example timeline after revert:**
```
10:00 - Created "Get Bread"
10:05 - Updated "Get French Bread"
10:10 - Updated "Get Sourdough Bread"
10:15 - Updated "Get French Bread"  ← Revert creates NEW event
```

---

## Edge Cases

### Clock Skew Between Devices

**Risk:** Device A's clock is ahead. User edits on Device A first, then Device B. Device A's edit has a "later" timestamp.

**Mitigation:** For single-actor use case, this is acceptable. User's most recent device wins. If needed later, could use server-assigned timestamps.

### Exact Timestamp Collision

**Risk:** Two events with identical millisecond timestamps (astronomically rare).

**Mitigation:** Add deterministic tiebreaker:

```swift
guard event.timestamp > stack.updatedAt ||
      (event.timestamp == stack.updatedAt &&
       event.id.uuidString > (stack.lastAppliedEventId ?? ""))
else { return }
```

### Out-of-Order Event Application

**Scenario:** Device B's event (10:05) arrives before Device A's event (10:00) due to network timing.

**Behavior:** LWW guard handles this correctly - A's event skipped because 10:00 < 10:05.

### Delete Then Update Arrives

**Scenario:** Stack deleted at 10:10, update from another device (10:05) arrives later.

**Behavior:** Skip updates to deleted entities with `guard !stack.isDeleted else { return }`.

---

## Testing Scenarios

1. **Single device offline edit** - Should work as before
2. **Two devices, sequential edits** - Latest timestamp wins
3. **Two devices, concurrent offline edits** - Latest timestamp wins deterministically
4. **Events arrive out of order** - Same final state regardless of arrival order
5. **Revert to previous version** - Creates new event, history preserved
6. **View history** - Shows all changes chronologically

---

## Why Not More Complex Solutions?

| Solution | Why Not |
|----------|---------|
| Revision OCC | Still has conflicts when same revision on multiple devices |
| Vector Clocks | Overkill for single-actor, adds complexity |
| CRDTs (complex) | LWW IS a CRDT - the simplest one that fits this use case |
| Operational Transform | For collaborative text editing, not full-object updates |

LWW by timestamp is the correct and sufficient solution for single-actor, full-object updates with offline-first sync.
