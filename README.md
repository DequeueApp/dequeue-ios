# Dequeue

Native iOS, iPadOS, and macOS task management app built with SwiftUI and SwiftData.

## Requirements

- Xcode 26.0+
- iOS 18.2+ / iPadOS 18.2+ / macOS 26.0+
- Swift 6.0+

## Tech Stack

| Layer | Technology |
|-------|------------|
| UI | SwiftUI |
| Data | SwiftData |
| Networking | URLSession (WebSocket + HTTP) |
| Concurrency | Swift Concurrency (async/await, actors) |
| Auth | Clerk iOS SDK |
| Error Tracking | Sentry iOS SDK |

## Getting Started

1. Open `Dequeue.xcodeproj` in Xcode
2. Select your target device/simulator
3. Build and run (⌘R)

## Development

### Running Tests

```bash
# Run all tests
xcodebuild test -project Dequeue.xcodeproj -scheme Dequeue -destination 'platform=macOS'

# Run specific test suite
xcodebuild test -project Dequeue.xcodeproj -scheme Dequeue -destination 'platform=macOS' -only-testing:DequeueTests/TaskServiceTests

# Run tests in Xcode
⌘U (or Product > Test)
```

### Code Quality

```bash
# Lint code (from Dequeue/ directory)
cd Dequeue && swiftlint lint

# Auto-fix violations
cd Dequeue && swiftlint --fix
```

**Important:** Always run SwiftLint and build locally before pushing. CI quota is limited.

## Architecture

```
Dequeue/
├── DequeueApp.swift          # App entry point
├── Config/                   # Environment configuration
├── Models/                   # SwiftData models
├── Services/                 # Business logic layer
├── Sync/                     # Sync infrastructure
├── Views/                    # SwiftUI views
├── ViewModels/               # @Observable view models
└── Extensions/               # Swift extensions
```

## Features

- **Hierarchical Tasks** — Stacks contain Tasks, drag-to-reorder
- **Arcs** — Group stacks into themes/epics for higher-level planning
- **Multi-Device Sync** — Real-time sync via WebSocket, offline-first
- **Search** — Unified search across tasks and stacks
- **Statistics** — Dashboard with completion rates, streaks, and priority breakdown
- **Batch Operations** — Multi-select tasks to complete, move, or delete in bulk
- **Reminders** — Push notifications with snooze and due date tracking
- **Tags** — Organize and filter stacks with color-coded tags
- **Attachments** — File attachments with upload/download management
- **Data Export** — Export your data to JSON
- **Webhooks** — Manage webhook integrations with delivery logs
- **Cross-Platform** — iPhone, iPad (split view), and Mac (sidebar navigation)
- **Keyboard Shortcuts** — ⌘N (new stack), ⌘T (new task), ⌘, (settings) on macOS

## Testing

The project uses Swift Testing framework (not XCTest). Test files live in `DequeueTests/`.

### Test Structure

```swift
import Testing
@testable import Dequeue

@Suite("Service Tests", .serialized)
@MainActor
struct MyServiceTests {
    @Test("description of test")
    func testSomething() async throws {
        // Given
        let container = try makeTestContainer()
        
        // When
        let result = try await doSomething()
        
        // Then
        #expect(result == expected)
    }
}
```

### Coverage

The project has **50+ unit test files** and **6 UI test files** covering core functionality:

**Unit Tests (DequeueTests/):**
- ✅ **Core Services:** TaskService (30 tests), StackService (31 tests), TagService, EventService, ReminderService, DeviceService
- ✅ **Sync Infrastructure:** SyncManager (performance, WebSocket, conflicts), ProjectorService
- ✅ **Attachments:** AttachmentService, UploadService, DownloadManager, FileCache, ThumbnailGenerator
- ✅ **API Clients:** APIKeyService, AuthService, SearchService, StatsService, ExportService, WebhookService, BatchService
- ✅ **ViewModels:** SyncStatusViewModel, AppTheme, UndoCompletionManager
- ✅ **Models:** Stack, Task, Tag, Attachment filtering and relationships
- ✅ **Features:** ActiveTaskTracking, ActiveStackConstraint, StartDueDates, ActivityFeed

**UI Tests (DequeueUITests/):**
- ✅ Authentication flow (2FA, device verification)
- ✅ Stack creation and management
- ✅ Task creation and completion
- ✅ Reminder creation and scheduling

**Note:** Some edge case tests are `.disabled` pending investigation (e.g., ProjectorService LWW timing issues).

## CI/CD

GitHub Actions runs on every PR:
- SwiftLint (code style)
- Claude Code Review (AI review)
- Build (iOS + macOS)
- Unit Tests
- UI Tests
- SonarCloud (code analysis)

**All checks must pass before merge.** CI runs can take 50-60+ minutes on macOS runners.

## Related Repositories

- [stacks](https://github.com/DequeueApp/stacks) - React Native version (deprecated)
- [stacks-sync](https://github.com/DequeueApp/stacks-sync) - Sync backend service

## License

Private - All rights reserved
