# Subtasks Feature (DEQ-29)

**Status:** ✅ Backend Implemented (Feb 13, 2026) | UI Pending  
**PRs:** iOS #276, API #50, API docs #52

## Overview

Support for hierarchical task relationships - tasks can have parent-child relationships to represent subtasks.

## Implementation Status

### ✅ Completed (Backend Infrastructure)

#### iOS Model Layer (PR #276)
- Added `parentTaskId: String?` field to `QueueTask` model
- Added `hasParent` computed property for quick parent checks
- SwiftData schema migration handled automatically
- Existing tasks default to `parentTaskId = nil` (no parent)

#### iOS Sync Layer (PR #276)
- `TaskEventPayload` includes `parentTaskId` for event processing
- `TaskState` includes `parentTaskId` for event sourcing
- `ProjectorService.applyTaskCreated` sets parentTaskId on task creation
- `ProjectorService.updateTask` handles parentTaskId updates

#### API Backend (PR #50)
- Database migration #015: Added `parent_task_id` column to tasks table
- Event payload supports parentTaskId field
- Task creation and update endpoints accept parentTaskId
- Documented in API README and OpenAPI spec (PR #52)

### 🚧 Pending (UI Layer)

The backend infrastructure is complete, but UI features are deferred:

- **Subtask hierarchy display** - Show parent-child relationships visually
- **Subtask creation** - UI for creating tasks as children of other tasks
- **Subtask assignment** - Move tasks to become subtasks of another task
- **Navigation** - Jump between parent and child tasks
- **Filtering** - Show/hide subtask trees
- **Completion logic** - Rules for parent completion when children complete

## Technical Details

### Data Model

```swift
// QueueTask.swift
@Model
final class QueueTask {
    var parentTaskId: String?  // ID of parent task, nil if root-level
    var hasParent: Bool { parentTaskId != nil }
    // ...
}
```

### Event Schema

```swift
// TaskEventPayload
struct TaskEventPayload {
    var parentTaskId: String?  // Optional parent task ID
    // ...
}
```

### Database Schema

```sql
-- Migration 015
ALTER TABLE tasks ADD COLUMN parent_task_id TEXT;
CREATE INDEX idx_tasks_parent_task_id ON tasks(parent_task_id);
```

## Usage Patterns (When UI is Implemented)

### Creating a Subtask

```swift
// Example (when UI exists)
let childTask = QueueTask(
    id: UUID().uuidString,
    title: "Subtask",
    stackId: stack.id,
    parentTaskId: parentTask.id,  // Link to parent
    // ...
)
```

### Querying Subtasks

```swift
// Example (when UI exists)
@Query(filter: #Predicate<QueueTask> { task in
    task.parentTaskId == parentTaskId && !task.isDeleted
})
var subtasks: [QueueTask]
```

### Root-Level Tasks Only

```swift
// Example (when UI exists)
@Query(filter: #Predicate<QueueTask> { task in
    task.parentTaskId == nil && !task.isDeleted
})
var rootTasks: [QueueTask]
```

## Design Considerations

### Recursion Depth
- Should enforce maximum nesting depth (e.g., 5 levels)
- Prevent circular references (task cannot be its own ancestor)

### Completion Behavior
Options to consider:
1. **Independent** - Child completion doesn't affect parent
2. **Auto-complete parent** - When all children complete, complete parent
3. **Block parent** - Parent cannot complete until all children complete

### Display Options
- **Flat list** - Show all tasks, indent subtasks visually
- **Collapsible tree** - Expand/collapse subtask groups
- **Breadcrumb navigation** - Show path: Stack > Task > Subtask

### Filtering
- "Show only root tasks" - Hide all subtasks
- "Show subtasks of X" - Filter to specific parent
- "Show all tasks flat" - Ignore hierarchy

## Next Steps

1. Design UI mockups for subtask hierarchy display
2. Implement subtask creation flow
3. Add unit tests for parent-child operations
4. Add UI tests for subtask workflows
5. Decide on completion behavior rules
6. Add settings for subtask display preferences

## Related Features

- **Arcs** - Subtasks inherit parent's arc by default
- **Tags** - Subtasks can have independent tags
- **Due dates** - Parent due date may constrain child due dates
- **Priority** - Subtasks may inherit or override parent priority

## References

- Linear Ticket: DEQ-29
- iOS PR: #276 (merged Feb 13, 2026)
- API PR: #50 (merged Feb 12, 2026)
- API Docs PR: #52 (merged Feb 12, 2026)
- Database Migration: 015 (add parent_task_id)

---

*Last updated: 2026-02-14 by Ada*
