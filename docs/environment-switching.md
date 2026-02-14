# Environment Switching (DEQ-59)

**Status:** ✅ Implemented (Feb 13, 2026)  
**PR:** #280

## Overview

Support for switching between Development, Staging, and Production environments in debug builds, enabling testing against different backend environments without rebuilding the app.

## Implementation

### Core Components

#### Environment Enum
```swift
enum Environment: String, CaseIterable {
    case development
    case staging
    case production
}
```

#### EnvironmentConfiguration
Defines environment-specific settings:
- Clerk publishable key
- Sentry DSN
- Dequeue API base URL
- Sync service base URL
- Sync app ID

#### EnvironmentManager
- `@Observable` service for environment management
- Singleton pattern (`EnvironmentManager.shared`)
- Persists selection in UserDefaults (debug only)
- Logs environment changes to Sentry for debugging
- Thread-safe environment switching

### Environment-Specific Configuration

| Setting | Development | Staging | Production |
|---------|------------|---------|------------|
| **Sync App ID** | `dequeue-development` | `dequeue-staging` | `dequeue` |
| **API Base URL** | Dev endpoint | Staging endpoint | Prod endpoint |
| **Sync Base URL** | Dev WebSocket | Staging WebSocket | Prod WebSocket |
| **Clerk Key** | Dev publishable key | Staging key | Prod key |
| **Sentry DSN** | Dev DSN | Staging DSN | Prod DSN |

## Usage

### Debug Builds
1. Open **Settings** app
2. Enable **Developer Mode**
3. Navigate to **Developer** section
4. Tap **Environment**
5. Select desired environment (🛠️ Dev / 🧪 Staging / 🚀 Prod)
6. Restart app for changes to take effect

### Release Builds
- **Locked to Production** - environment switching UI hidden
- Cannot switch environments in release builds
- Always uses production configuration

## Configuration Migration

The `Configuration` struct was refactored to use `EnvironmentManager` dynamically:

**Before:**
```swift
static let clerkPublishableKey: String = "pk_test_..."
static let syncAppId: String = "dequeue"
```

**After:**
```swift
static var clerkPublishableKey: String {
    EnvironmentManager.shared.configuration.clerkPublishableKey
}
static var syncAppId: String {
    EnvironmentManager.shared.configuration.syncAppId
}
```

## Features

### Compile-Time Safety
- Uses `#if DEBUG` to hide switcher in release builds
- Production builds physically cannot switch environments
- Type-safe environment enum prevents invalid states

### Persistence
- Environment selection saved in UserDefaults (debug only)
- Persists across app restarts
- Reset to default environment capability

### Logging & Debugging
- Environment switches logged to Sentry as breadcrumbs
- Current environment visible in debug menu
- Configuration details displayed for verification

### UI Components
- **EnvironmentSwitcherView** - SwiftUI picker for environment selection
- **Environment badge** - Visual indicator (🛠️ 🧪 🚀)
- **Configuration display** - Shows current URLs and app IDs
- **Reset button** - Restore default environment

## Backend Coordination

The backend must support different app IDs:
- **Development:** `dequeue-development`
- **Staging:** `dequeue-staging`
- **Production:** `dequeue`

Switching to an environment without a corresponding backend app ID will cause sync failures until the app ID is created in the backend.

## Testing

### Unit Tests
Comprehensive test coverage via `EnvironmentManagerTests`:
- Environment switching logic
- Persistence in debug builds
- Production lock in release builds
- Configuration loading per environment
- Thread safety

Run tests:
```bash
xcodebuild test -scheme Dequeue \
  -destination 'platform=macOS' \
  -only-testing:DequeueTests/EnvironmentManagerTests
```

### Manual Testing Checklist
- [ ] Enable Developer Mode in Settings
- [ ] Verify environment switcher appears in Developer section
- [ ] Switch to Development - verify URLs change
- [ ] Switch to Staging - verify URLs change
- [ ] Switch to Production - verify URLs change
- [ ] Restart app - verify environment persists
- [ ] Reset to default - verify returns to Development (debug)
- [ ] Build release - verify switcher hidden

## Security Considerations

### API Keys
- Development and Staging keys should be different from Production
- Rotate keys if they're accidentally committed to source control
- Use different Clerk projects per environment when possible

### Data Isolation
- Development/Staging data should NOT mix with Production
- Users should use test accounts in non-production environments
- Sync app IDs ensure data isolation at the backend level

### Sentry
- Consider separate Sentry projects per environment
- Prevents dev/staging errors from polluting production metrics
- Enables environment-specific error budgets

## Future Enhancements

### Visual Indicators
- **App icon badge** - Overlay indicating non-production environment
- **Banner** - Persistent banner in UI showing current environment
- **Navigation bar tint** - Color-code environment (amber for staging, etc.)

### Configuration Management
- **Remote config** - Load environment URLs from backend
- **Dynamic environments** - Add/remove environments without app update
- **Feature flags** - Enable/disable features per environment

### Developer Experience
- **Quick switch** - Shake gesture to open environment switcher
- **Debug overlay** - Show environment in corner of every screen
- **Network inspector** - View API requests per environment
- **Clear data** - Reset local database when switching environments

### Monitoring
- **Environment-specific Sentry projects** - Better error isolation
- **Environment tags** - Tag all events with current environment
- **Analytics separation** - Track metrics per environment

## Troubleshooting

### "Failed to sync after switching environments"
**Cause:** Backend doesn't have app ID for new environment  
**Solution:** Create app ID (`dequeue-development` or `dequeue-staging`) in backend

### "Environment persists after switching back"
**Cause:** UserDefaults cache  
**Solution:** Use "Reset to Default" button or reinstall app

### "Can't find environment switcher"
**Cause:** Developer Mode not enabled  
**Solution:** Open Settings > Developer Mode toggle

### "Environment switcher missing in release build"
**Expected:** Release builds are locked to production  
**Solution:** Use debug build for environment switching

## Related

- Linear Ticket: DEQ-59
- PR: #280 (merged Feb 13, 2026)
- Related file: `Dequeue/Configuration.swift`
- Related file: `Dequeue/Services/EnvironmentManager.swift`
- Related file: `Dequeue/Views/Settings/EnvironmentSwitcherView.swift`

---

*Last updated: 2026-02-14 by Ada*
