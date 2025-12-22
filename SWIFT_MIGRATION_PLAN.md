# Dequeue Swift Rewrite Plan

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

| Milestone | Status | Progress |
|-----------|--------|----------|
| 1. Foundation | **In Progress** | ~95% |
| 2. Core Data Operations | **In Progress** | ~90% |
| 3. UI Screens | **In Progress** | ~95% |
| 4. Sync | **Complete** | ~100% |
| 5. Notifications | **Not Started** | 0% |
| 6. Platform Polish | **In Progress** | ~50% |

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

### Milestone 1: Foundation
- [x] Create new GitHub repo (`dequeue-ios`)
- [x] Create Xcode project with SwiftUI multiplatform template
- [ ] Set up GitHub Actions for CI/CD:
  - [ ] Build & test workflow (on PR and push)
  - [ ] SwiftLint for code quality
  - [ ] TestFlight deployment (on main branch merge)
  - [ ] Sentry release/sourcemap upload
- [x] Set up SwiftData models (5 of 7 entities - missing SyncQueue, SyncHistory)
- [x] Configure Clerk iOS SDK
- [x] Set up Sentry iOS SDK
- [x] Create basic app shell with tab navigation

### Milestone 2: Core Data Operations
- [x] Implement StackService
- [x] Implement TaskService
- [ ] Implement ReminderService
- [x] Implement EventService
- [x] Create basic CRUD UI for Stacks/Tasks (partial - Add/View implemented)

### Milestone 3: UI Screens
- [x] HomeView with drag-to-reorder
- [x] StackDetailView
- [x] TaskDetailView
- [x] AddStackView with drafts
- [x] CompletedStacksView
- [x] DraftsView

### Milestone 4: Sync
- [x] SyncManager actor
- [x] WebSocket connection
- [x] Push/Pull operations
- [x] ProjectorService for incoming events
- [x] Proper lastSyncedAt tracking with nextCheckpoint
- [x] Device discovery events
- [x] Sync debug view

### Milestone 5: Notifications & Polish
- [ ] NotificationService
- [ ] Schedule/cancel local notifications
- [ ] Handle notification taps
- [ ] NotificationsView
- [ ] Badge management

### Milestone 6: Platform Polish
- [x] macOS sidebar navigation (in MainTabView)
- [ ] iPad optimizations
- [ ] Keyboard shortcuts
- [x] Settings view (with devices, developer mode)
- [x] Devices view (showing connected devices)
- [x] Event log viewer (for debugging)
- [x] Developer settings toggle
- [ ] Final testing & polish

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
