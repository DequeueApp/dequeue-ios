# Dequeue iOS - Gap Analysis

This document provides a comprehensive analysis of gaps between the intended product vision (as defined in `PROJECT.md`) and the current implementation. Each section details what exists, what's missing, and specific action items.

---

## Table of Contents

1. [Core Constraints & Focus Model](#1-core-constraints--focus-model)
2. [Stack & Task Model](#2-stack--task-model)
3. [Event-First Architecture](#3-event-first-architecture)
4. [Sync Model](#4-sync-model)
5. [Reminders System](#5-reminders-system)
6. [AI-Native Features](#6-ai-native-features)
7. [Services Layer](#7-services-layer)
8. [UI/UX Implementation](#8-uiux-implementation)
9. [Platform Support](#9-platform-support)
10. [Testing & Quality](#10-testing--quality)
11. [Configuration & Security](#11-configuration--security)

---

## 1. Core Constraints & Focus Model

### Intent (from PROJECT.md)
> - Exactly one active Stack at a time
> - Exactly one active Task within the active Stack
> - Other stacks and tasks may exist, but are inactive

### Current State
- **Partial Implementation**: Multiple stacks can have `status == .active` simultaneously
- The "active" stack is determined by `sortOrder == 0` (first in list)
- The "active" task is determined by first pending task in `pendingTasks` (sorted by `sortOrder`)
- No explicit enforcement of the "exactly one" constraint

### Gaps

| Gap | Priority | Description |
|-----|----------|-------------|
| [ ] No explicit active stack tracking | HIGH | Need a mechanism to ensure only one stack is truly "active" at any time |
| [ ] No deactivation event when activating another | HIGH | When activating stack B, stack A should be explicitly deactivated |
| [ ] `activeTask` is computed, not persisted | MEDIUM | Consider explicit tracking for sync correctness |
| [ ] No constraint validation in services | MEDIUM | `StackService.setAsActive()` doesn't deactivate others fully |

### Recommended Actions
1. Add `isActive` boolean field to Stack model OR enforce via status
2. Create explicit `stack.deactivated` event when another stack becomes active
3. Add validation in `StackService` to ensure constraint is maintained
4. Consider adding `activeStackId` to a settings/user-preferences model

---

## 2. Stack & Task Model

### Intent (from PROJECT.md)
> Tasks within a stack preserve rich metadata:
> - Creation time
> - Last-active time
> - Blocked / waiting state
> - Optional parent relationships

### Current State

**Stack Model** (`Models/Stack.swift`):
- Has: `createdAt`, `updatedAt`, `status`, `priority`, `sortOrder`, `tags`, `attachments`
- Has: Location fields (address, lat/long)
- Has: `startTime`, `dueTime`

**QueueTask Model** (`Models/QueueTask.swift`):
- Has: `createdAt`, `updatedAt`, `status`, `priority`, `sortOrder`
- Has: `blockedReason` for blocked state
- Has: Location fields (address, lat/long)
- Has: `dueTime`
- Missing: `lastActiveTime`
- Missing: Parent task relationship

### Gaps

| Gap | Priority | Description |
|-----|----------|-------------|
| [ ] Missing `lastActiveTime` on QueueTask | HIGH | Per PROJECT.md, tasks should track when they were last active |
| [ ] No parent task relationships | MEDIUM | PROJECT.md mentions "optional parent relationships" |
| [ ] No `waiting` status distinct from `blocked` | LOW | Consider if waiting (on external) differs from blocked (internal) |
| [ ] `tags` only on Stack, not Task | LOW | Tasks may benefit from tagging too |
| [ ] `attachments` stored as `[String]` URLs only | LOW | No attachment metadata (type, size, preview) |
| [ ] No `startTime` on QueueTask | LOW | Only `dueTime` exists |

### Recommended Actions
1. Add `lastActiveTime: Date?` to `QueueTask` model
2. Update `TaskService.activateTask()` to set `lastActiveTime = Date()`
3. Add `var parentTask: QueueTask?` relationship (self-referential)
4. Add corresponding `task.activated` event to record activation time

---

## 3. Event-First Architecture

### Intent (from PROJECT.md)
> - Every change is expressed as an event
> - Clients do not mutate state directly - They emit events, then rehydrate projections from the same pipeline
> - There is a single canonical source of truth: the event stream

### Current State
- Events ARE recorded for all operations (via `EventService`)
- However, SwiftData entities are the local source of truth
- `ProjectorService` applies incoming sync events TO SwiftData models
- No "event replay" capability - cannot rebuild state from events alone
- Local changes mutate SwiftData directly, then record event

### Gaps

| Gap | Priority | Description |
|-----|----------|-------------|
| [ ] State is not derived from events | HIGH | SwiftData is source of truth, not event stream |
| [ ] No event replay/rebuild capability | MEDIUM | Cannot reconstruct state from event history |
| [ ] Local mutations happen before event recording | MEDIUM | Should emit event first, then apply |
| [ ] `revertToHistoricalState` creates new event but doesn't use event as source | LOW | Works correctly but pattern differs from pure event-sourcing |

### Recommended Actions
1. **Decision Point**: Determine if true event-sourcing is needed or current "event-assisted sync" is sufficient
2. If pure event-sourcing desired:
   - Add `rebuildFromEvents()` capability to `ProjectorService`
   - Consider using events as write model, SwiftData as read projection
3. If current approach is acceptable:
   - Document that this is "event-logging" not "event-sourcing"
   - Ensure all state changes record events BEFORE mutating

---

## 4. Sync Model

### Intent (from PROJECT.md)
> - Offline-first by default
> - Cloud sync is built-in for v1
> - Conflict resolution is Last Write Wins (LWW)
> - Events are pushed to other devices (near real-time)

### Current State
- **Implemented**: Offline-first with local SwiftData storage
- **Implemented**: WebSocket connection for real-time push
- **Implemented**: HTTP push/pull for event sync
- **Implemented**: LWW using event timestamps in `ProjectorService`
- **Implemented**: Device tracking and filtering

### Gaps

| Gap | Priority | Description |
|-----|----------|-------------|
| [ ] No offline queue indicator in UI | MEDIUM | User can't see pending sync count |
| [ ] No manual sync trigger in main UI | LOW | Only in developer settings |
| [ ] No sync conflict notification | LOW | LWW happens silently |
| [ ] WebSocket reconnection could be more robust | LOW | Basic exponential backoff exists |
| [ ] No sync progress indicator | LOW | No visual feedback during sync |

### Recommended Actions
1. Add sync status indicator to main UI (pending event count, last sync time)
2. Consider adding subtle sync indicator (like iCloud sync dots)
3. Add pull-to-refresh that triggers manual sync

---

## 5. Reminders System

### Intent (from PROJECT.md)
> - Reminders are first-class entities
> - Can attach to: Tasks, Stacks
> - Support: One-time reminders, Snoozing, (Future) recurrence
> - Trigger local notifications with actions
> - All reminder actions emit events

### Current State

**Model** (`Models/Reminder.swift`):
- Has: `parentId`, `parentType` (stack/task), `remindAt`, `status`, `snoozedFrom`
- Has: Sync fields, `isDeleted`
- Relationships exist on Stack and QueueTask

**EventService**:
- Has: `recordReminderCreated`, `recordReminderUpdated`, `recordReminderDeleted`
- Has: `reminderSnoozed` event type

**UI**:
- `TaskDetailView` shows reminders but cannot create them
- `StackDetailView` has no reminder UI
- No reminder creation/edit sheet

**Missing**:
- No `ReminderService` for business logic
- No local notification scheduling
- No notification actions
- No snooze UI/functionality

### Gaps

| Gap | Priority | Description |
|-----|----------|-------------|
| [ ] No `ReminderService` | CRITICAL | Core business logic missing |
| [ ] No reminder creation UI | CRITICAL | Users cannot create reminders |
| [ ] No local notification scheduling | CRITICAL | `UNUserNotificationCenter` not integrated |
| [ ] No snooze functionality | HIGH | Model supports it, no implementation |
| [ ] No reminder edit UI | HIGH | Cannot modify existing reminders |
| [ ] No notification permission request | HIGH | Need to request at appropriate time |
| [ ] No notification actions (complete, snooze) | MEDIUM | Quick actions from notification |
| [ ] No reminder deletion UI | MEDIUM | Cannot remove reminders |
| [ ] No recurring reminders | LOW | Marked as future in PROJECT.md |
| [ ] FIXMEs in code referencing reminder work | MEDIUM | `TaskDetailView.swift:277` |

### Recommended Actions

1. **Create `ReminderService`** (`Services/ReminderService.swift`):
   ```swift
   @MainActor
   final class ReminderService {
       func createReminder(for task: QueueTask, at date: Date) throws -> Reminder
       func createReminder(for stack: Stack, at date: Date) throws -> Reminder
       func updateReminder(_ reminder: Reminder, remindAt: Date) throws
       func snoozeReminder(_ reminder: Reminder, until: Date) throws
       func deleteReminder(_ reminder: Reminder) throws
       func getUpcomingReminders() throws -> [Reminder]
   }
   ```

2. **Create notification infrastructure**:
   - Add `NotificationService` to handle `UNUserNotificationCenter`
   - Request permissions on first reminder creation
   - Schedule/cancel notifications when reminders change
   - Handle notification actions (complete task, snooze)

3. **Create UI components**:
   - `AddReminderSheet` for creating reminders
   - `ReminderRowView` for displaying in lists
   - Snooze picker (15 min, 1 hour, tomorrow, etc.)

4. **Update existing views**:
   - Add "Add Reminder" button to `TaskDetailView`
   - Add reminder section to `StackDetailView`
   - Add reminders tab/section to `MainTabView` or home

---

## 6. AI-Native Features

### Intent (from PROJECT.md)
> Dequeue assumes:
> - Tasks may be delegated to AI agents
> - AI work is asynchronous
> - Results return later
> - Context must survive that delay
>
> AI may:
> - Complete tasks
> - Propose new tasks
> - Reorder tasks
> - Attach reminders

### Current State
- **Not Implemented**: No AI-related fields or functionality exists
- No mechanism to track task ownership/responsibility
- No way to mark a task as "delegated to AI"
- No incoming mechanism for AI to make changes

### Gaps

| Gap | Priority | Description |
|-----|----------|-------------|
| [ ] No task delegation tracking | MEDIUM | Need to track if task is delegated to AI |
| [ ] No AI actor/agent identification | MEDIUM | Events don't distinguish human vs AI |
| [ ] No "pending AI response" status | MEDIUM | Tasks can be blocked but not specifically waiting on AI |
| [ ] No AI proposal mechanism | LOW | How would AI propose tasks? |
| [ ] No AI-created event tracking | LOW | `deviceId` exists but no `actorType` |

### Recommended Actions

1. **Add fields to QueueTask**:
   ```swift
   var delegatedToAI: Bool = false
   var aiAgentId: String? // Which AI agent is working on this
   var aiDelegatedAt: Date?
   ```

2. **Add event metadata**:
   ```swift
   struct EventMetadata: Codable {
       let actorType: ActorType // .human, .ai
       let actorId: String?
       let aiAgentName: String?
   }

   enum ActorType: String, Codable {
       case human
       case ai
   }
   ```

3. **Add new event types**:
   - `task.delegatedToAI`
   - `task.aiCompleted`
   - `task.aiProposed`

4. **Create AI integration endpoints** (future, needs backend support)

---

## 7. Services Layer

### Current Services

| Service | Exists | Test Coverage | Notes |
|---------|--------|---------------|-------|
| `StackService` | Yes | NO | Core CRUD, missing tests |
| `TaskService` | Yes | Partial | Has tests, good coverage |
| `EventService` | Yes | Partial | Has tests |
| `ReminderService` | NO | - | CRITICAL GAP |
| `AuthService` | Yes | NO | Clerk integration |
| `DeviceService` | Yes | Partial | Has tests |
| `ErrorReportingService` | Yes | NO | Sentry integration |
| `SyncManager` | Yes | NO | Complex, needs tests |
| `ProjectorService` | Yes | NO | Critical for sync |

### Gaps

| Gap | Priority | Description |
|-----|----------|-------------|
| [ ] Missing `ReminderService` | CRITICAL | See Reminders section |
| [ ] Missing `NotificationService` | CRITICAL | For local notifications |
| [ ] No `StackService` tests | HIGH | Core functionality untested |
| [ ] No `SyncManager` tests | HIGH | Complex async code untested |
| [ ] No `ProjectorService` tests | HIGH | Critical sync code untested |
| [ ] No `AuthService` tests | MEDIUM | Mock exists but not tested |

### Recommended Actions
1. Create `ReminderService` (priority 1)
2. Create `NotificationService` (priority 2)
3. Add comprehensive tests for all services
4. Consider creating `StackServiceTests.swift`

---

## 8. UI/UX Implementation

### Current Views

| View | Status | Issues |
|------|--------|--------|
| `HomeView` | Complete | Works correctly |
| `StackDetailView` | Mostly Complete | Missing reminder UI |
| `TaskDetailView` | Mostly Complete | Missing reminder creation |
| `AddStackView` | Complete | Auto-save draft works |
| `AddTaskSheet` | Complete | Basic functionality |
| `DraftsView` | Complete | Works correctly |
| `CompletedStacksView` | Partial | No tap action to view details |
| `StackHistoryView` | Complete | Revert functionality works |
| `AuthView` | Complete | 2FA support included |
| `SettingsView` | Partial | Notifications/Appearance placeholders |
| `EventLogView` | Complete | Developer tool |
| `SyncDebugView` | Complete | Developer tool |
| `DevicesView` | Complete | Shows connected devices |

### Gaps & FIXMEs in Code

| Location | Issue | Priority |
|----------|-------|----------|
| `HomeView.swift:46-47` | FIXME: Notifications button does nothing | HIGH |
| `StackDetailView.swift:271-272` | FIXME: Uncomplete task not implemented | MEDIUM |
| `TaskDetailView.swift:277` | FIXME: Add reminder button missing | HIGH |
| `SettingsView.swift:56-57` | Notifications/Appearance are placeholders | MEDIUM |
| `Configuration.swift:17-19` | FIXME: Replace Clerk key placeholder | LOW (has real key) |

### Additional UI Gaps

| Gap | Priority | Description |
|-----|----------|-------------|
| [ ] No reminder creation UI | CRITICAL | Cannot create reminders |
| [ ] No reminder list view | HIGH | No dedicated view for all reminders |
| [ ] `CompletedStacksView` items not tappable | MEDIUM | Can't view completed stack details |
| [ ] No keyboard shortcuts on macOS | MEDIUM | PROJECT.md mentions ⌘N, ⌘S, etc. |
| [ ] No sync status in main UI | MEDIUM | Can't see if data is syncing |
| [ ] No pull-to-refresh | LOW | Common UX pattern missing |
| [ ] No haptic feedback | LOW | Would improve feel |
| [ ] Notifications bell does nothing | HIGH | Placeholder button |
| [ ] No task uncomplete functionality | MEDIUM | Can complete but not uncomplete |

### Recommended Actions

1. **Implement notifications UI** (bell icon in HomeView):
   - Show upcoming reminders
   - Show overdue reminders
   - Quick snooze/dismiss actions

2. **Add reminder creation**:
   - Add button in `TaskDetailView` reminders section
   - Create `AddReminderSheet`
   - Support common presets (1 hour, tomorrow, next week)

3. **Fix CompletedStacksView**:
   - Make rows tappable
   - Navigate to read-only stack detail view

4. **Implement Settings**:
   - Notifications settings (request permissions, configure)
   - Appearance settings (if supporting themes)

---

## 9. Platform Support

### Intent (from CLAUDE.md)
> - Use TabView for main navigation (iOS)
> - Use NavigationSplitView for sidebar navigation (macOS)
> - Support keyboard shortcuts (macOS): ⌘N, ⌘S, etc.
> - Support Dynamic Type
> - Handle safe areas properly
> - Support both orientations

### Current State
- iOS: TabView navigation implemented
- macOS: NavigationSplitView implemented
- iPad: Uses iOS layout (TabView)

### Gaps

| Gap | Priority | Description |
|-----|----------|-------------|
| [ ] No keyboard shortcuts (macOS) | MEDIUM | ⌘N for new stack, etc. not implemented |
| [ ] No iPad-specific layout | LOW | Could use split view on larger iPads |
| [ ] Dynamic Type not verified | LOW | Need to test all views |
| [ ] No landscape-specific layouts | LOW | Works but not optimized |
| [ ] No Mac Catalyst considerations | LOW | If supporting Catalyst |

### Recommended Actions

1. Add keyboard shortcuts for macOS:
   ```swift
   .keyboardShortcut("n", modifiers: .command) // New stack
   .keyboardShortcut("t", modifiers: .command) // New task
   ```

2. Add iPad split view for larger screens
3. Audit all views for Dynamic Type support
4. Test on all device sizes and orientations

---

## 10. Testing & Quality

### Current Test Coverage

| Test File | Coverage | Notes |
|-----------|----------|-------|
| `TaskServiceTests.swift` | Good | Core task operations |
| `StackTests.swift` | Basic | Model tests, one flaky test disabled |
| `StackFilteringTests.swift` | Good | Filter logic verified |
| `EventTests.swift` | Basic | Event model tests |
| `DeviceTests.swift` | Unknown | Need to verify |
| `DequeueTests.swift` | Unknown | Need to verify |
| UI Tests | Empty | `DequeueUITests.swift` is placeholder |

### Gaps

| Gap | Priority | Description |
|-----|----------|-------------|
| [ ] No `StackService` tests | HIGH | Core service untested |
| [ ] No `ReminderService` tests | HIGH | (Service doesn't exist yet) |
| [ ] No `SyncManager` tests | HIGH | Complex async logic untested |
| [ ] No `ProjectorService` tests | HIGH | Critical sync projection untested |
| [ ] No `EventService` integration tests | MEDIUM | Only basic model tests |
| [ ] UI tests are empty | MEDIUM | No automated UI testing |
| [ ] No sync integration tests | MEDIUM | End-to-end sync untested |
| [ ] Flaky test disabled | LOW | `pendingTasksFiltersCorrectly` |
| [ ] No performance tests | LOW | Could add for sync operations |

### Recommended Actions

1. **Create service tests** (priority order):
   - `StackServiceTests.swift`
   - `ReminderServiceTests.swift` (when service exists)
   - `SyncManagerTests.swift` (mock network)
   - `ProjectorServiceTests.swift`

2. **Create UI tests**:
   - Authentication flow
   - Create stack flow
   - Create task flow
   - Complete stack flow

3. **Fix flaky test**:
   - Investigate `pendingTasksFiltersCorrectly`
   - Remove `.disabled` once fixed

---

## 11. Configuration & Security

### Current State
- Clerk publishable key hardcoded (appropriate for client)
- Sentry DSN hardcoded
- Sync API URL hardcoded

### Gaps

| Gap | Priority | Description |
|-----|----------|-------------|
| [ ] No environment switching | LOW | Same keys for DEBUG/RELEASE |
| [ ] No certificate pinning | LOW | For production security |
| [ ] Auth tokens stored in memory only | LOW | Consider Keychain for persistence |

### Recommended Actions
1. Consider using `.xcconfig` files for environment-specific values
2. Add certificate pinning for production API calls
3. Evaluate token storage strategy

---

## Summary: Priority Action Items

### Critical (Must Have for v1)
1. [ ] Create `ReminderService` with full CRUD operations
2. [ ] Create `NotificationService` for local notifications
3. [ ] Add reminder creation UI in `TaskDetailView`
4. [ ] Implement notification bell functionality in `HomeView`
5. [ ] Request notification permissions appropriately

### High Priority
1. [ ] Add `lastActiveTime` to QueueTask model
2. [ ] Enforce "one active stack" constraint properly
3. [ ] Add `StackService` test coverage
4. [ ] Add `SyncManager` test coverage
5. [ ] Add `ProjectorService` test coverage
6. [ ] Make `CompletedStacksView` items tappable
7. [ ] Implement task uncomplete functionality

### Medium Priority
1. [ ] Add sync status indicator to main UI
2. [ ] Add parent task relationships
3. [ ] Implement Settings > Notifications properly
4. [ ] Add macOS keyboard shortcuts
5. [ ] Consider AI delegation field structure
6. [ ] Create UI tests

### Low Priority
1. [ ] Add iPad-specific layouts
2. [ ] Add Dynamic Type verification
3. [ ] Add pull-to-refresh
4. [ ] Add certificate pinning
5. [ ] Add recurring reminder support
6. [ ] Performance testing

---

## Appendix: Code Locations for Reference

### Models
- `Dequeue/Models/Stack.swift`
- `Dequeue/Models/QueueTask.swift`
- `Dequeue/Models/Reminder.swift`
- `Dequeue/Models/Event.swift`
- `Dequeue/Models/Device.swift`
- `Dequeue/Models/Enums.swift`

### Services
- `Dequeue/Services/StackService.swift`
- `Dequeue/Services/TaskService.swift`
- `Dequeue/Services/EventService.swift`
- `Dequeue/Services/AuthService.swift`
- `Dequeue/Services/DeviceService.swift`
- `Dequeue/Services/ErrorReportingService.swift`

### Sync
- `Dequeue/Sync/SyncManager.swift`
- `Dequeue/Sync/ProjectorService.swift`

### Views
- `Dequeue/Views/Home/HomeView.swift`
- `Dequeue/Views/Stack/*.swift`
- `Dequeue/Views/Task/*.swift`
- `Dequeue/Views/Settings/*.swift`
- `Dequeue/Views/Auth/AuthView.swift`
- `Dequeue/Views/App/MainTabView.swift`

### Tests
- `DequeueTests/TaskServiceTests.swift`
- `DequeueTests/StackTests.swift`
- `DequeueTests/StackFilteringTests.swift`
- `DequeueTests/EventTests.swift`
