# Dequeue Swift Rewrite Plan

> **Migration Status:** ~85% Complete
>
> Core app functionality is complete and exceeds the React Native version. Remaining work focuses on notifications, CI/CD, and platform-specific polish.

## Overview

Complete rewrite of Dequeue (Stacks) from React Native to native Swift, targeting iOS 18+, iPadOS, and macOS via SwiftUI multiplatform.

### Technology Stack

| Layer | Technology | Notes |
|-------|------------|-------|
| UI | **SwiftUI** | iOS 18+ features, native on all platforms |
| Data | **SwiftData** | Modern persistence, replaces WatermelonDB |
| Networking | **URLSession** | WebSocket + HTTP for sync |
| Concurrency | **Swift Concurrency** | async/await, actors, structured concurrency |
| Auth | **Clerk iOS SDK** | Keep existing auth infrastructure |
| Notifications | **UserNotifications** | Local + push notifications |
| Error Tracking | **Sentry iOS SDK** | Keep existing error tracking |

### Target Platforms

- **iOS 18.0+** (iPhone)
- **iPadOS 18.0+** (iPad)
- **macOS 15.0+** (Sequoia, via SwiftUI multiplatform)

---

## Migration Progress Summary

| Milestone | Status | Progress | Remaining Work |
|-----------|--------|----------|----------------|
| 1. Foundation | ✅ **Complete** (except CI/CD) | ~95% | GitHub Actions setup |
| 2. Core Data Operations | ✅ **Complete** (except Reminders) | ~90% | ReminderService |
| 3. UI Screens | ✅ **Complete** | ~95% | Minor polish |
| 4. Sync | ✅ **Complete** | 100% | None |
| 5. Notifications | ❌ **Not Started** | 0% | Full implementation needed |
| 6. Platform Polish | 🟡 **In Progress** | ~50% | iPad, keyboard shortcuts, testing |

---

## Phase 1: Project Setup & Core Architecture

### 1.1 Xcode Project Structure

```
Dequeue/
├── DequeueApp.swift              # ✅ App entry point
├── Config/
│   ├── Configuration.swift       # ✅ API URLs, feature flags
│   └── Constants.swift           # ⏳ Not yet created
├── Models/                       # SwiftData models
│   ├── Stack.swift               # ✅
│   ├── QueueTask.swift           # ✅ (renamed from Task to avoid Swift.Task conflict)
│   ├── Reminder.swift            # ✅
│   ├── Event.swift               # ✅
│   ├── Device.swift              # ✅
│   ├── SyncQueue.swift           # ⏳ Not yet created
│   └── SyncHistory.swift         # ⏳ Not yet created
├── Services/                     # Business logic layer
│   ├── StackService.swift        # ✅
│   ├── TaskService.swift         # ✅
│   ├── ReminderService.swift     # ⏳ Not yet created
│   ├── EventService.swift        # ✅
│   ├── DeviceService.swift       # ✅
│   ├── AuthService.swift         # ✅
│   ├── ErrorReportingService.swift # ✅
│   ├── NotificationService.swift # ⏳ Not yet created
│   └── DraftService.swift        # ⏳ Not yet created
├── Sync/                         # Sync infrastructure
│   ├── SyncManager.swift         # ✅
│   └── ProjectorService.swift    # ✅
├── Views/                        # SwiftUI views
│   ├── App/
│   │   ├── MainTabView.swift     # ✅
│   │   └── ContentView.swift     # ✅
│   ├── Home/
│   │   ├── HomeView.swift        # ✅
│   │   └── StackRowView.swift    # ✅ (inline in HomeView)
│   ├── Stack/
│   │   ├── StackDetailView.swift # ✅
│   │   ├── AddStackView.swift    # ✅
│   │   └── CompletedStacksView.swift # ✅
│   ├── Task/
│   │   ├── TaskDetailView.swift  # ✅
│   │   └── TaskRowView.swift     # ✅ (inline in StackDetailView)
│   ├── Drafts/
│   │   └── DraftsView.swift      # ✅
│   ├── Notifications/
│   │   └── NotificationsView.swift # ⏳ Not yet created
│   ├── Settings/
│   │   ├── SettingsView.swift    # ✅
│   │   ├── DevicesView.swift     # ✅
│   │   ├── EventLogView.swift    # ✅
│   │   └── SyncDebugView.swift   # ✅
│   ├── Auth/
│   │   ├── AuthView.swift        # ✅
│   │   ├── SignInView.swift      # ⏳ (embedded in AuthView)
│   │   └── SignUpView.swift      # ⏳ (embedded in AuthView)
│   └── Components/               # Reusable components
│       ├── ReminderPicker.swift  # ⏳ Not yet created
│       ├── EventLogView.swift    # ⏳ Not yet created
│       └── LoadingView.swift     # ⏳ Not yet created
├── ViewModels/                   # @Observable view models
│   ├── HomeViewModel.swift       # ⏳ (using @Query directly)
│   ├── StackDetailViewModel.swift # ⏳ Not yet created
│   ├── AuthViewModel.swift       # ⏳ (using AuthService directly)
│   └── SyncStatusViewModel.swift # ⏳ Not yet created
├── Extensions/
│   ├── Date+Extensions.swift     # ⏳ Not yet created
│   └── String+Extensions.swift   # ⏳ Not yet created
└── Resources/
    ├── Assets.xcassets           # ✅
    └── Localizable.xcstrings     # ⏳ Not yet created
```

### 1.2 Dependencies (Swift Package Manager)

```swift
// ✅ Package dependencies configured
dependencies: [
    .package(url: "https://github.com/clerk/clerk-ios", from: "1.0.0"),  // ✅
    .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.0.0"),  // ✅
]
```

### 1.3 Core Architecture Patterns

**@Observable + SwiftData** - ✅ Pattern established

**Actor-based Services** - ✅ SyncManager implemented as actor

---

## Phase 6: Implementation Order

### Milestone 1: Foundation ✅ (95% - CI/CD Pending)
- [x] ✅ Create new GitHub repo (`dequeue-ios`)
- [x] ✅ Create Xcode project with SwiftUI multiplatform template
- [ ] ⏳ **REMAINING:** Set up GitHub Actions for CI/CD:
  - [ ] Build & test workflow (on PR and push)
  - [ ] SwiftLint for code quality
  - [ ] TestFlight deployment (on main branch merge)
  - [ ] Sentry release/sourcemap upload
- [x] ✅ Set up SwiftData models (Core models complete - SyncQueue/SyncHistory not needed)
- [x] ✅ Configure Clerk iOS SDK
- [x] ✅ Set up Sentry iOS SDK
- [x] ✅ Create basic app shell with tab navigation

### Milestone 2: Core Data Operations ✅ (90% - ReminderService Pending)
- [x] ✅ Implement StackService
- [x] ✅ Implement TaskService
- [ ] ⏳ **REMAINING:** Implement ReminderService (deferred until notifications milestone)
- [x] ✅ Implement EventService
- [x] ✅ Create comprehensive CRUD UI for Stacks/Tasks

### Milestone 3: UI Screens ✅ (100% Complete)
- [x] ✅ HomeView with drag-to-reorder
- [x] ✅ StackDetailView with full editing capabilities
- [x] ✅ TaskDetailView with status management
- [x] ✅ AddStackView with drafts
- [x] ✅ CompletedStacksView
- [x] ✅ DraftsView
- [x] ✅ Event history views for debugging

### Milestone 4: Sync ✅ (100% Complete)
- [x] ✅ SyncManager actor with concurrent operations
- [x] ✅ WebSocket connection with reconnection handling
- [x] ✅ Push/Pull operations with immediate sync
- [x] ✅ ProjectorService for incoming events with LWW
- [x] ✅ Proper lastSyncedAt tracking with nextCheckpoint
- [x] ✅ Device discovery events
- [x] ✅ Sync debug view with comprehensive event logging

### Milestone 5: Notifications & Polish ❌ (0% - Not Started)
- [ ] ⏳ **REMAINING:** NotificationService
- [ ] ⏳ **REMAINING:** Schedule/cancel local notifications
- [ ] ⏳ **REMAINING:** Handle notification taps
- [ ] ⏳ **REMAINING:** NotificationsView
- [ ] ⏳ **REMAINING:** Badge management

**Note:** This milestone is the primary remaining work for feature parity with React Native version.

### Milestone 6: Platform Polish 🟡 (50% In Progress)
- [x] ✅ macOS sidebar navigation (in MainTabView)
- [ ] ⏳ **REMAINING:** iPad optimizations (split view, multitasking)
- [ ] ⏳ **REMAINING:** Keyboard shortcuts (⌘N, ⌘S, etc.)
- [x] ✅ Settings view (with devices, developer mode)
- [x] ✅ Devices view (showing connected devices)
- [x] ✅ Event log viewer (for debugging)
- [x] ✅ Developer settings toggle
- [ ] ⏳ **REMAINING:** Final testing & polish

---

## Known Issues / Bugs

1. **UI Freeze on TextField Focus** - Partially addressed by presenting AddStackView as sheet, may need further investigation
2. **Draft functionality** - Basic save/discard implemented but needs testing

---

## Decisions

| Question | Decision |
|----------|----------|
| Data Migration | **Fresh start** - no migration from RN app |
| App Store | **New app listing** - brand new app |
| Widgets | **Fast follow** - after initial release |
| Apple Watch | **Fast follow** - after initial release |
| Clerk iOS SDK | ✅ Verified - SDK supports email + verification code flow |
| Project Location | ✅ **New repo** - `dequeue-ios` |
| Task Model Name | ✅ Renamed to `QueueTask` to avoid Swift.Task conflict |

---

## Future Enhancements (Post-Launch)

### Phase 7: Widgets (Fast Follow)
- [ ] Create Widget extension target
- [ ] "Current Stack" widget showing active stack + top task
- [ ] "Quick Add" widget for adding new stacks
- [ ] Multiple widget sizes (small, medium, large)
- [ ] Lock Screen widgets (iOS 18)

### Phase 8: Apple Watch (Fast Follow)
- [ ] Create watchOS target
- [ ] View active stacks list
- [ ] View tasks in current stack
- [ ] Mark tasks complete from watch
- [ ] Complications for current task
- [ ] Notification mirroring

---

## Next Priority Items

1. **StackDetailView** - View and edit existing stacks, manage tasks
2. **TaskDetailView** - View and edit individual tasks
3. **ReminderService** - Support for task/stack reminders
4. **NotificationService** - Local push notifications
5. **GitHub Actions CI/CD** - Automated builds and TestFlight deployment

---

## Completed Work Log

- **2024-12**: Initial project setup, models, basic views
- **2024-12**: Clerk SDK integration with sign in/up flows
- **2024-12**: Sentry error tracking integration
- **2024-12**: SyncManager with WebSocket, push/pull operations
- **2024-12**: ProjectorService for applying sync events
- **2024-12**: Fixed MainActor isolation issues in sync layer
- **2024-12**: Fixed QueueTask naming conflict with Swift.Task
- **2024-12**: AddStackView sheet presentation and draft save/discard
- **2025-12**: Fixed backend to accept UUID format (36 chars) for event IDs
- **2025-12**: Fixed AddStackView to properly record events via StackService/TaskService
- **2025-12**: Implemented proper lastSyncedAt tracking using nextCheckpoint from backend
- **2025-12**: Implemented device.discovered event on first launch
- **2025-12**: Added DevicesView showing connected devices with metadata
- **2025-12**: Added developer settings toggle in Settings
- **2025-12**: Added EventLogView for viewing/filtering sync events
- **2025-12**: Added SyncDebugView for debugging sync state
- **2025-12**: Updated ProjectorService to handle incoming device.discovered events
- **2025-12**: Implemented LWW (Last-Writer-Wins) sync with String IDs using CUID generator
- **2025-12**: Fixed event payload format to match React Native exactly (state wrapper pattern)
- **2025-12**: Added StackHistoryView for viewing entity event history
- **2025-12**: Implemented StackDetailView with description editing, task management, completion flows
- **2025-12**: Implemented TaskDetailView with title/description editing, status changes, event history
