# Dequeue Migration Gap Analysis

**React Native → Swift Migration Status**

Last Updated: 2026-01-03

---

## Summary

| Category | Complete | Remaining | Progress |
|----------|----------|-----------|----------|
| Models | 5/5 | 0 | ✅ 100% |
| Core Services | 6/8 | 2 | 🟡 75% |
| Sync Infrastructure | 2/2 | 0 | ✅ 100% |
| UI Views | 13/15 | 2 | 🟡 87% |
| Platform Polish | 4/8 | 4 | 🟡 50% |
| CI/CD | 0/4 | 4 | ⏳ 0% |

**Overall: ~85% Complete**

---

## Models

| Model | Status | Notes |
|-------|--------|-------|
| Stack.swift | ✅ DONE | Full properties, sync fields, relationships |
| QueueTask.swift | ✅ DONE | Renamed from Task to avoid Swift.Task conflict |
| Reminder.swift | ✅ DONE | Status tracking, parent polymorphism |
| Event.swift | ✅ DONE | Event sourcing, RN payload compatibility |
| Device.swift | ✅ DONE | Multi-device tracking, hardware ID |
| SyncQueue.swift | ⏳ NOT NEEDED | Draft model, sync works without it |
| SyncHistory.swift | ⏳ NOT NEEDED | Draft model, sync works without it |

---

## Services

| Service | Status | Notes |
|---------|--------|-------|
| StackService.swift | ✅ DONE | CRUD, drafts, history revert, status transitions |
| TaskService.swift | ✅ DONE | CRUD, status workflow, reordering |
| EventService.swift | ✅ DONE | Event recording, RN-compatible payloads |
| DeviceService.swift | ✅ DONE | Device discovery, hardware detection |
| AuthService.swift | ✅ DONE | Clerk SDK, sign in/up, verification codes |
| ErrorReportingService.swift | ✅ DONE | Sentry integration, breadcrumbs |
| ReminderService.swift | ⏳ TODO | Model exists, service not implemented |
| NotificationService.swift | ⏳ TODO | Local push notifications, badge management |
| DraftService.swift | ⏳ NOT NEEDED | Logic embedded in StackService |

---

## Sync Infrastructure

| Component | Status | Notes |
|-----------|--------|-------|
| SyncManager.swift | ✅ DONE | Actor-based, WebSocket, push/pull, auto-reconnect |
| ProjectorService.swift | ✅ DONE | LWW conflict resolution, all event types handled |

---

## UI Views

| View | Status | Notes |
|------|--------|-------|
| MainTabView.swift | ✅ DONE | Tab-based iOS, sidebar macOS |
| ContentView.swift | ✅ DONE | App shell, auth gating |
| AuthView.swift | ✅ DONE | Sign in/up with verification |
| HomeView.swift | ✅ DONE | Dashboard, drag-to-reorder |
| StackDetailView.swift | ✅ DONE | Edit, tasks, completion workflow |
| AddStackView.swift | ✅ DONE | Draft auto-save, discard confirmation |
| CompletedStacksView.swift | ✅ DONE | Archive of completed stacks |
| StackHistoryView.swift | ✅ DONE | Event history with revert |
| TaskDetailView.swift | ✅ DONE | Edit, status changes, block/unblock |
| DraftsView.swift | ✅ DONE | Work-in-progress drafts |
| SettingsView.swift | ✅ DONE | Account, developer mode toggle |
| DevicesView.swift | ✅ DONE | Connected devices with metadata |
| EventLogView.swift | ✅ DONE | Event log viewer with filtering |
| SyncDebugView.swift | ✅ DONE | Sync state debugging |
| NotificationsView.swift | ⏳ TODO | Notification history/management |
| ReminderPicker.swift | ⏳ TODO | Component for scheduling reminders |

---

## Platform Polish

| Feature | Status | Notes |
|---------|--------|-------|
| macOS sidebar navigation | ✅ DONE | In MainTabView |
| Developer settings toggle | ✅ DONE | In SettingsView |
| Event log viewer | ✅ DONE | In EventLogView |
| Sync debug view | ✅ DONE | In SyncDebugView |
| iPad optimizations | ⏳ TODO | Split view, size classes |
| macOS keyboard shortcuts | ⏳ TODO | ⌘N, ⌘S, etc. |
| Preferences UI | ⏳ TODO | Placeholders in SettingsView |
| Appearance settings | ⏳ TODO | Dark mode, themes |

---

## CI/CD

| Item | Status | Notes |
|------|--------|-------|
| Build & test workflow | ⏳ TODO | GitHub Actions on PR/push |
| SwiftLint enforcement | ⏳ TODO | .swiftlint.yml exists |
| TestFlight deployment | ⏳ TODO | On main branch merge |
| Sentry release upload | ⏳ TODO | Source maps, release tracking |

---

## Features Not Yet Implemented

### High Priority (MVP Blocking)

| Feature | Status | Dependency |
|---------|--------|------------|
| ReminderService | ⏳ TODO | None |
| NotificationService | ⏳ TODO | ReminderService |
| NotificationsView | ⏳ TODO | NotificationService |
| Badge management | ⏳ TODO | NotificationService |

### Medium Priority (Post-MVP Polish)

| Feature | Status | Notes |
|---------|--------|-------|
| Search/filter stacks | ⏳ TODO | No search functionality yet |
| Tags management UI | ⏳ TODO | Model field exists |
| Attachment handling | ⏳ TODO | Model fields exist, no upload/view |
| Location support | ⏳ TODO | Model fields exist, no map |
| Uncomplete task action | ⏳ TODO | TODO in StackDetailView:252 |

### Lower Priority (Fast Follow)

| Feature | Status | Notes |
|---------|--------|-------|
| Widget extension | ⏳ TODO | Current stack widget |
| Apple Watch app | ⏳ TODO | View/complete tasks |
| Localization | ⏳ TODO | Localizable.xcstrings |

---

## Known TODOs in Code

```
Configuration.swift:17     // TODO: Replace with your actual Clerk publishable key
Configuration.swift:37     // TODO: Use "dequeue-development" for DEBUG when backend supports it
HomeView.swift:35          // TODO: Show notifications
TaskDetailView.swift:273   // TODO: Add reminder button when ReminderService is implemented
StackDetailView.swift:252  // TODO: Implement uncomplete if needed
```

---

## Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Data migration | Fresh start | No migration from RN app |
| App Store | New listing | Brand new app |
| Task model name | QueueTask | Avoid Swift.Task conflict |
| ViewModels | @Query directly | Simpler, works well with SwiftData |
| Constants.swift | Not created | Using inline constants for now |
| Extensions | Not created | Not needed yet |

---

## What's Working Well

1. **Sync is rock solid** - WebSocket + LWW conflict resolution + RN payload compatibility
2. **Event sourcing complete** - Full audit trail with history revert
3. **Multi-device support** - Device discovery and tracking working
4. **Core CRUD operations** - Stacks and tasks fully functional
5. **Draft management** - Auto-save with discard confirmation
6. **Error tracking** - Sentry integration with breadcrumbs

---

## Recommended Next Steps

### Phase 1: Notifications (Required for MVP)
1. Implement `ReminderService` (create, cancel, snooze reminders)
2. Implement `NotificationService` (schedule local notifications)
3. Add `ReminderPicker` component to TaskDetailView
4. Create `NotificationsView` for notification history
5. Wire up bell button in HomeView

### Phase 2: Polish
1. Add search/filter to HomeView
2. Implement macOS keyboard shortcuts
3. iPad split view optimization
4. Complete Preferences UI in Settings

### Phase 3: CI/CD
1. Set up GitHub Actions for build/test
2. Configure TestFlight deployment
3. Add Sentry release tracking

---

## Test Coverage

| Test File | Status | Notes |
|-----------|--------|-------|
| StackTests.swift | ✅ DONE | Model initialization, filtering |
| EventTests.swift | ✅ DONE | Encoding/decoding |
| DeviceTests.swift | ✅ DONE | Device identification |
| DequeueTests.swift | ✅ DONE | Basic app tests |
| DequeueUITests.swift | ✅ DONE | Launch tests |

**Known Issue:** Flaky test for pendingTasks filtering (disabled)
