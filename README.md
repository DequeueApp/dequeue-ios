# Dequeue

Native iOS, iPadOS, and macOS task management app built with SwiftUI and SwiftData.

## Requirements

- Xcode 16.0+
- iOS 18.0+ / iPadOS 18.0+ / macOS 15.0+
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

- **Hierarchical Tasks** - Stacks contain Tasks, drag-to-reorder
- **Multi-Device Sync** - Real-time sync via WebSocket
- **Offline-First** - Full local database, sync when online
- **Reminders** - Push notifications with snooze
- **Cross-Platform** - iPhone, iPad, and Mac

## Related Repositories

- [stacks](https://github.com/DequeueApp/stacks) - React Native version (deprecated)
- [stacks-sync](https://github.com/DequeueApp/stacks-sync) - Sync backend service

## License

Private - All rights reserved
