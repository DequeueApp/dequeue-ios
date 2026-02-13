# AI Delegation Implementation Notes

**Created:** 2026-02-05  
**Last Updated:** 2026-02-13  
**Status:** Phase 2 Complete (UI & Foundation)  
**Related PRs:** #248 (DEQ-54), #249 (DEQ-56), #259 (DEQ-58), #260 (DEQ-57)

## Overview

AI delegation enables users to assign tasks to AI agents for autonomous completion. This feature supports Dequeue's AI-native vision (see ROADMAP.md #3: LLM Task Delegation).

## Architecture

### Phase 1: Foundation (DEQ-54, DEQ-56)

Lays groundwork for tracking which tasks are delegated to AI agents:

**Model Changes (PR #248 / DEQ-54):**
- Added `delegatedToAI: Bool` to `QueueTask` (default: false)
- Added `aiAgentId: String?` to track which agent is handling the task
- Added `aiDelegatedAt: Date?` to track when delegation occurred

**Event Types (PR #249 / DEQ-56):**
- New event type: `task.delegatedToAI`
- Payload includes: taskId, stackId, aiAgentId, aiAgentName, fullState
- Projector applies these events to update task AI fields

### Data Flow

```
User toggles "Delegate to AI"
  ↓
EventService.recordTaskDelegatedToAI()
  ↓
Event persisted locally + queued for sync
  ↓
ProjectorService applies event
  ↓
QueueTask updated with AI fields
  ↓
Event syncs to backend
  ↓
Backend notifies AI agent (future)
  ↓
AI works on task asynchronously (future)
  ↓
AI reports back via new events (future)
```

## Implementation Details

### QueueTask Model

```swift
@Model
final class QueueTask {
    // ... existing fields ...
    
    // AI Delegation (DEQ-54)
    var delegatedToAI: Bool = false
    var aiAgentId: String?
    var aiDelegatedAt: Date?
}
```

**Migration:** No migration needed - new optional fields with safe defaults.

### TaskEventPayload

AI delegation fields added to event payloads:

```swift
struct TaskEventPayload: Codable {
    // ... existing fields ...
    
    // AI Delegation (DEQ-54)
    let delegatedToAI: Bool?
    let aiAgentId: String?
    let aiDelegatedAt: Int64?  // Unix timestamp
}
```

**Encoding/Decoding:** Handles Date ↔ Int64 timestamp conversion for JSON compatibility.

### Event Type

```swift
// Enums.swift
extension EventType {
    static let taskDelegatedToAI = "task.delegatedToAI"
}
```

### EventService Method

```swift
func recordTaskDelegatedToAI(
    _ task: QueueTask,
    aiAgentId: String,
    aiAgentName: String
) async throws {
    let payload = TaskDelegatedToAIPayload(
        taskId: task.id,
        stackId: task.stackId,
        aiAgentId: aiAgentId,
        aiAgentName: aiAgentName,
        fullState: TaskState.from(task)
    )
    
    try recordEvent(
        type: .taskDelegatedToAI,
        payload: payload,
        entityId: task.id
    )
}
```

### ProjectorService Handler

```swift
func applyTaskDelegatedToAI(_ payload: TaskDelegatedToAIPayload) async throws {
    guard let task = getTask(payload.taskId) else {
        os_log("[Projector] Task not found: \(payload.taskId)")
        return
    }
    
    // Apply AI delegation fields from fullState
    task.delegatedToAI = payload.fullState.delegatedToAI ?? false
    task.aiAgentId = payload.fullState.aiAgentId
    task.aiDelegatedAt = payload.fullState.aiDelegatedAt
    
    try context.save()
}
```

## Future Phases

### Phase 2: UI & Workflow ✅ COMPLETE (DEQ-58, PR #259)

**Implemented:** February 11, 2026

- ✅ Toggle switch on Task detail view: "Delegate to AI"
- ✅ Visual indicator showing task is delegated (badge, icon)
- ✅ Show AI agent name and delegation timestamp
- ✅ "Cancel delegation" action
- ✅ `task.aiCompleted` event type added (DEQ-57, PR #252, #260)
- ✅ UI display configuration for AI-completed tasks (PR #260)

### Phase 3: Backend Integration

- Backend receives `task.delegatedToAI` events
- Backend notifies AI agent service
- AI agent begins work on task
- Status updates stream back to client

### Phase 4: AI Results & Completion

- New event types:
  - `task.aiProgressUpdate` - AI reports progress
  - `task.aiCompleted` - AI marks task done with results
  - `task.aiBlocked` - AI encounters blockers
- Results attached as task attachments or inline in description
- User reviews and accepts/modifies AI work

## Testing Strategy

### Unit Tests (Phase 1)

- ✅ TaskEventPayload serialization with AI fields
- ✅ ProjectorService applies `task.delegatedToAI` events
- ✅ Backward compatibility (old events without AI fields)

### Integration Tests (Future)

- Mock AI agent responds to delegation
- End-to-end flow: delegate → AI works → result appears

## Open Questions

- **Agent Selection:** How does user choose which AI agent? (hardcoded initially?)
- **Cancellation:** What happens if user cancels delegation mid-work?
- **Failure Handling:** What if AI fails? Retry? Notify user?
- **Cost Tracking:** Should we track AI API costs per task?

## Related Documents

- ROADMAP.md #3: LLM Task Delegation (high-level vision)
- PROJECT.md: AI-Native Assumptions (design philosophy)

---

*This is a living document. Update as implementation progresses.*
