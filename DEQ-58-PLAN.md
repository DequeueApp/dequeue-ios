# DEQ-58: AI Delegation UI Implementation Plan

**Status:** ✅ IMPLEMENTED  
**Implementation:** PR #259 (merged February 11, 2026)  
**Dependencies:** DEQ-54 ✅ merged, DEQ-56 ✅ merged  
**Actual Time:** ~2 hours

## Goal

Add UI controls to TaskDetailView for delegating tasks to AI agents.

## User Stories

1. As a user, I want to delegate a task to an AI agent so it can work on it autonomously
2. As a user, I want to see which tasks are currently delegated to AI
3. As a user, I want to cancel AI delegation if I change my mind
4. As a user, I want to see when a task was delegated and to which agent

## UI Changes

### TaskDetailView - Delegation Section

Add new section between "Details" and "Attachments":

```swift
Section("AI Delegation") {
    if task.delegatedToAI {
        // Show delegation status
        VStack(alignment: .leading, spacing: 8) {
            Label("Delegated to AI", systemImage: "sparkles.rectangle.stack.fill")
                .foregroundStyle(.purple)
            
            if let agentName = task.aiAgentId {
                Text("Agent: \(agentName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let delegatedAt = task.aiDelegatedAt {
                Text("Since: \(delegatedAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Button("Cancel Delegation", role: .destructive) {
                Task { await cancelDelegation() }
            }
        }
    } else {
        // Show delegation button
        Button {
            Task { await delegateToAI() }
        } label: {
            Label("Delegate to AI", systemImage: "sparkles.rectangle.stack")
        }
    }
}
```

### TaskRow - Visual Indicator

Add subtle badge when task is delegated:

```swift
HStack {
    // ... existing task row content ...
    
    if task.delegatedToAI {
        Image(systemName: "sparkles.rectangle.stack.fill")
            .font(.caption)
            .foregroundStyle(.purple.opacity(0.7))
    }
}
```

## Service Changes

### TaskService - New Methods

```swift
/// Delegate task to AI agent
func delegateToAI(_ task: QueueTask, agentId: String = "default-agent") async throws {
    // 1. Record event via EventService
    try await eventService.recordTaskDelegatedToAI(
        task,
        aiAgentId: agentId,
        aiAgentName: "OpenClaw Agent" // TODO: Make configurable
    )
    
    // 2. Trigger sync
    try await syncManager.sync()
}

/// Cancel AI delegation
func cancelAIDelegation(_ task: QueueTask) async throws {
    // Record event to clear AI fields
    // (Uses existing recordTaskUpdated with AI fields set to nil)
    try await eventService.recordTaskUpdated(task) // with AI fields cleared
    try await syncManager.sync()
}
```

## Agent Selection (Phase 1: Hardcoded)

For MVP, hardcode a single "default agent":
- Agent ID: `"default-agent"`
- Agent Name: `"OpenClaw Agent"`

Future enhancement: Agent picker/dropdown

## Testing Strategy

### Manual Testing
1. Open task detail
2. Click "Delegate to AI"
3. Verify:
   - Badge appears in task row
   - Delegation section shows agent info and timestamp
   - "Cancel Delegation" button works
   - Events recorded correctly (check via event history)
4. Sync to another device
5. Verify delegation state syncs correctly

### Unit Tests
- `TaskServiceTests.testDelegateToAI()`
- `TaskServiceTests.testCancelAIDelegation()`
- `EventServiceTests.testRecordTaskDelegatedToAI()` (already exists from DEQ-56)

### UI Tests
- Navigate to task detail
- Tap delegate button
- Verify UI updates

## Open Questions

1. **Error Handling:** What if event recording fails? Show alert?
2. **Permissions:** Should delegation require confirmation? (Leaning: No, it's just an event)
3. **Agent Name:** Hardcode or make configurable in Settings? (Leaning: Hardcode for MVP)
4. **Bulk Operations:** Support delegating multiple tasks at once? (Future)

## Implementation Steps

1. **Add UI to TaskDetailView** (~15 min)
   - Delegation section
   - Conditional rendering based on `task.delegatedToAI`
   
2. **Add badge to TaskRow** (~5 min)
   - Small sparkles icon when delegated

3. **Add TaskService methods** (~10 min)
   - `delegateToAI()`
   - `cancelAIDelegation()`

4. **Wire up view to service** (~10 min)
   - Call service methods from button actions
   - Handle errors

5. **Manual testing** (~10 min)
   - Create task, delegate, cancel
   - Verify sync

6. **Write unit tests** (~20 min)
   - Service method tests
   - Event recording tests

7. **Create PR** (~5 min)
   - Descriptive title/body
   - Link to DEQ-58

**Total:** ~75 minutes

## Success Criteria

- [ ] User can delegate task to AI from TaskDetailView
- [ ] Delegated tasks show visual indicator (badge)
- [ ] Delegation status displays agent name and timestamp
- [ ] User can cancel delegation
- [ ] Delegation state syncs across devices
- [ ] All tests pass
- [ ] SwiftLint + Claude Code review pass

## Future Enhancements (Not in Scope)

- Agent picker (choose from multiple agents)
- Bulk delegation (delegate multiple tasks)
- Delegation history view
- AI progress updates in UI
- Smart agent selection (based on task type)

---

**Ready to implement once DEQ-56 merges!**
