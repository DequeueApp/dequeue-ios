# AI Delegation System

## Overview

The AI Delegation System enables tracking and management of tasks that are delegated to AI agents for automated completion. This feature set distinguishes between human and AI actors, records delegation events, and tracks AI-completed work.

## Feature Chain

The system is built across three Linear tickets:

1. **DEQ-56** - `task.delegatedToAI` event type (✅ Shipped)
2. **DEQ-55** - Actor metadata infrastructure (✅ Shipped PR #251)
3. **DEQ-57** - `task.aiCompleted` event type (✅ Shipped PR #252)
4. **DEQ-58** - UI for AI delegation status (🔜 Next)

## Architecture

### Actor Metadata (DEQ-55)

All events can now include metadata distinguishing human vs AI actors.

**Types:**
```swift
/// Distinguishes whether an event was created by a human user or an AI agent
enum ActorType: String, Codable, CaseIterable {
    case human  // Event created by a human user
    case ai     // Event created by an AI agent
}

/// Metadata attached to events to track who/what created them
struct EventMetadata: Codable {
    var actorType: ActorType
    var actorId: String?  // AI agent identifier (required when actorType is .ai)
}
```

**Convenience Methods:**
```swift
// Create metadata
let humanMeta = EventMetadata.human()
let aiMeta = EventMetadata.ai(agentId: "agent-123")

// Check event actor type
if event.isFromAI {
    print("AI agent: \(event.actorMetadata()?.actorId ?? "unknown")")
}
```

**Event Model Extensions:**
```swift
extension Event {
    /// Decode the event's metadata as EventMetadata
    func actorMetadata() throws -> EventMetadata?
    
    /// Check if this event was created by an AI agent
    var isFromAI: Bool
    
    /// Check if this event was created by a human user
    var isFromHuman: Bool
}
```

### Event Types

#### task.delegatedToAI (DEQ-56)

Created when a **human** delegates a task to an AI agent.

**Actor:** Human (the person delegating)

**Payload:**
```swift
struct TaskDelegatedToAIPayload: Codable {
    let taskId: String
    let stackId: String
    let aiAgentId: String       // ID of the AI agent assigned
    let aiAgentName: String?    // Human-readable name
    let fullState: TaskState    // Complete task snapshot
}
```

**Usage:**
```swift
try await eventService.recordTaskDelegatedToAI(
    task,
    aiAgentId: "agent-007",
    aiAgentName: "CodeBot"
)
```

#### task.aiCompleted (DEQ-57)

Created when an **AI agent** completes a task.

**Actor:** AI (the agent completing the work)

**Payload:**
```swift
struct TaskAICompletedPayload: Codable {
    let taskId: String
    let stackId: String
    let aiAgentId: String       // ID of the AI agent that completed it
    let aiAgentName: String?    // Human-readable name
    let resultSummary: String?  // What the AI accomplished
    let fullState: TaskState    // Complete task snapshot
}
```

**Usage:**
```swift
try await eventService.recordTaskAICompleted(
    task,
    aiAgentId: "agent-007",
    aiAgentName: "CodeBot",
    resultSummary: "Refactored code and added comprehensive tests"
)
```

**Automatic AI Metadata:**  
This method automatically attaches `EventMetadata.ai(agentId: aiAgentId)` so the event is properly marked as AI-created.

## Event Service Integration

The `EventService.recordEvent()` method was updated to accept optional metadata:

```swift
private func recordEvent<T: Encodable>(
    type: EventType,
    payload: T,
    entityId: String? = nil,
    metadata: EventMetadata? = nil  // Defaults to .human() if nil
) async throws
```

**Default Behavior:**  
All events without explicit metadata are marked as human-created for backward compatibility.

## Querying AI-Related Events

### Check if Event is AI-Created

```swift
let events = try eventService.fetchHistory(for: taskId)
for event in events {
    if event.isFromAI {
        let metadata = try? event.actorMetadata()
        print("AI Agent: \(metadata?.actorId ?? "unknown")")
    }
}
```

### Filter AI Completion Events

```swift
let events = try eventService.fetchHistory(for: taskId)
let aiCompletions = events.filter { 
    $0.eventType == .taskAICompleted 
}
```

### Get AI Agent Details from Payload

```swift
let payload = try event.decodePayload(TaskAICompletedPayload.self)
print("Agent: \(payload.aiAgentName ?? payload.aiAgentId)")
print("Result: \(payload.resultSummary ?? "No summary")")
```

## UI Integration (DEQ-58 - Pending)

Once DEQ-58 is implemented, the UI will:

1. **Show delegation status**
   - Badge/icon on delegated tasks
   - Display which AI agent is assigned
   - Show delegation time

2. **Distinguish completion types**
   - AI-completed tasks marked differently from human-completed
   - Show AI agent name and result summary
   - Link to AI's work in event history

3. **Event history display**
   - "Delegated to CodeBot" for task.delegatedToAI events
   - "Completed by CodeBot: [summary]" for task.aiCompleted events
   - Visual distinction for AI vs human actors

## Testing

### Unit Tests

All components have comprehensive test coverage:

**EventTests.swift** (DEQ-55):
- EventMetadata factory methods
- Human actor metadata encoding/decoding
- AI actor metadata encoding/decoding
- Event.isFromAI / isFromHuman checks

**EventServiceTests.swift** (DEQ-57):
- recordTaskAICompleted creates correct event type
- AI actor metadata is attached automatically
- Payload includes all agent details and result summary

### Manual Testing Scenarios

1. **Delegate Task to AI**
   ```swift
   try await eventService.recordTaskDelegatedToAI(task, aiAgentId: "test-agent", aiAgentName: "TestBot")
   ```
   - Verify event created with type `task.delegatedToAI`
   - Check metadata shows `actorType = .human`

2. **AI Completes Task**
   ```swift
   try await eventService.recordTaskAICompleted(task, aiAgentId: "test-agent", aiAgentName: "TestBot", resultSummary: "Test completed")
   ```
   - Verify event created with type `task.aiCompleted`
   - Check metadata shows `actorType = .ai`
   - Check payload includes result summary

3. **Query Event History**
   ```swift
   let events = try eventService.fetchHistory(for: taskId)
   let aiEvents = events.filter { $0.isFromAI }
   ```
   - Verify only AI-completed events are returned
   - Check delegation events are not included (they're human-created)

## Future Extensions

### Additional AI Event Types

The actor metadata infrastructure supports tracking AI actions across the app:

- `stack.aiCreated` - AI creates a stack
- `task.aiUpdated` - AI modifies a task
- `reminder.aiCreated` - AI sets a reminder
- etc.

Simply pass `EventMetadata.ai(agentId: "...")` when recording these events.

### Multi-Agent Support

The `actorId` field enables tracking multiple AI agents:

```swift
let agent1Meta = EventMetadata.ai(agentId: "code-agent")
let agent2Meta = EventMetadata.ai(agentId: "research-agent")
```

### Agent Performance Analytics

Query all AI completions to analyze agent performance:

```swift
let allEvents = try eventService.fetchAllEvents()
let aiCompletions = allEvents.filter { 
    $0.eventType == .taskAICompleted 
}

// Group by agent
let byAgent = Dictionary(grouping: aiCompletions) { event -> String in
    (try? event.actorMetadata()?.actorId) ?? "unknown"
}
```

## Implementation Timeline

- **2026-02-06 @ 12:15 AM** - DEQ-55 implemented (PR #251)
- **2026-02-06 @ 12:45 AM** - DEQ-57 implemented (PR #252)
- **2026-02-06 @ 01:00 AM** - Documentation created
- **TBD** - DEQ-58 (UI) pending CI resolution

## References

- **PR #249** - DEQ-56 (task.delegatedToAI) - Already merged
- **PR #251** - DEQ-55 (actor metadata) - Pending CI
- **PR #252** - DEQ-57 (task.aiCompleted) - Pending CI
- **MEMORY.md** - "Swift 6 Actor Isolation & Codable" pattern used in implementation

---

*Last updated: 2026-02-06 @ 01:00 AM by Ada*
