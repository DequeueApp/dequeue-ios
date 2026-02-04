# Data Privacy & Export - PRD

**Feature:** Data Export, Account Deletion, Biometric Lock  
**Author:** Ada (Dequeue Engineer)  
**Date:** 2026-02-03  
**Status:** Draft  
**Related:** ROADMAP.md Section 9

## Problem Statement

Users entrust Dequeue with sensitive personal and professional information - their tasks, projects, work habits, and time tracking data. Without strong privacy controls and data portability, users face:

1. **Legal Risk (for us)**: GDPR Article 20 (Right to Data Portability) and Article 17 (Right to Erasure) are **legally required** for EU users
2. **Trust Issues**: Users hesitate to commit to apps when they can't easily leave
3. **Security Concerns**: Some users track sensitive work and want device-level protection (biometric lock)
4. **Vendor Lock-in Fear**: "What if Dequeue shuts down? Can I get my data out?"

**Real user concerns:**
- "Can I export my task history for tax/billing purposes?"
- "If I switch to another app, can I take my data with me?"
- "What if I need to delete my account? Will my data really be gone?"
- "Can I lock this app with Face ID? I track sensitive client work."

**Competitor benchmark:**
- Things 3: Export to JSON, encrypted backups
- OmniFocus: Full database export, encrypted sync
- Todoist: CSV export, GDPR-compliant deletion

**Without these features, we're not enterprise-ready and risk GDPR violations.**

## Solution

Implement three interconnected privacy features:

1. **Data Export**: Users can download all their data (Stacks, Tasks, Events, Attachments) in portable formats (JSON + ZIP)
2. **Account & Data Deletion**: Self-service account deletion that fully erases all user data (GDPR Right to Erasure)
3. **Biometric App Lock**: Optional Face ID / Touch ID protection when opening the app

**Key Principles:**
1. **User Control**: Users own their data and can take it anywhere
2. **Transparency**: Clear about what data is collected and how to delete it
3. **Compliance**: Meet GDPR requirements (not optional for EU users)
4. **Security without Friction**: Biometric lock is opt-in, not mandatory
5. **No Dark Patterns**: Deletion is easy, not hidden behind obstacles

## Features

### 1. Data Export

#### What's Exported

**Full data package includes:**
| Category | Format | Contents |
|----------|--------|----------|
| Stacks | JSON | All Stacks with full metadata (title, created, modified, active status) |
| Tasks | JSON | All Tasks with metadata (title, description, completed, blocked status) |
| Reminders | JSON | All Reminders with trigger times and repeat rules |
| Tags | JSON | All Tags and their associations |
| Events (Optional) | JSON | Full event history (for advanced users / auditing) |
| Attachments | Files + Manifest | All files in original format + JSON manifest mapping to Stacks/Tasks |

**JSON Schema Example:**
```json
{
  "exportVersion": "1.0",
  "exportDate": "2026-02-03T22:30:00Z",
  "user": {
    "userId": "uuid",
    "email": "user@example.com"
  },
  "stacks": [
    {
      "id": "uuid",
      "title": "API Integration",
      "description": "Backend API work",
      "createdAt": "2026-01-15T10:00:00Z",
      "modifiedAt": "2026-02-03T18:00:00Z",
      "isActive": true,
      "isArchived": false,
      "tasks": [ /* Task objects */ ]
    }
  ],
  "attachments": [
    {
      "id": "uuid",
      "filename": "design.pdf",
      "mimeType": "application/pdf",
      "fileKey": "attachments/abc123.pdf",  // Path in ZIP
      "attachedTo": {
        "type": "stack",
        "id": "uuid"
      }
    }
  ]
}
```

**Formats Available:**
- **JSON**: Full export (default) - machine-readable, preserves all data
- **CSV**: Simplified export (Stacks + Tasks only) - human-readable, Excel-friendly

#### User Flow

**Settings → Privacy → Export My Data**

1. User taps "Export My Data"
2. Sheet appears with options:
   ```
   Export Your Data
   
   What to include:
   [x] Stacks and Tasks (required)
   [x] Reminders
   [x] Tags
   [ ] Full Event History (advanced)
   [x] Attachments
   
   Format:
   ○ JSON (complete)
   ● CSV (simplified - no attachments)
   
   [Start Export]
   ```
3. User taps "Start Export"
4. Background processing begins (progress indicator)
5. Notification when ready: "Your data export is ready"
6. Share sheet appears → User can save to Files, AirDrop, email, etc.

**Large exports (>100 MB):**
- Warn user: "This export is large (237 MB). It may take a few minutes."
- Process in background
- Notify when ready

**Attachment handling:**
- If "Attachments" checked: ZIP file includes `attachments/` folder + `export.json` manifest
- If unchecked: JSON includes attachment metadata (filename, ID) but not the files themselves

#### Technical Implementation

**Export Service:**
```swift
actor DataExportService {
    func exportAllData(
        includeEvents: Bool,
        includeAttachments: Bool,
        format: ExportFormat
    ) async throws -> URL {
        // 1. Fetch all entities from SwiftData
        let stacks = try await fetchAllStacks()
        let tasks = try await fetchAllTasks()
        let reminders = try await fetchAllReminders()
        
        // 2. Serialize to JSON/CSV
        let data: Data
        switch format {
        case .json:
            data = try encodeToJSON(stacks: stacks, tasks: tasks, ...)
        case .csv:
            data = try encodeToCSV(stacks: stacks, tasks: tasks)
        }
        
        // 3. If attachments included, create ZIP
        if includeAttachments {
            return try await createZIPArchive(
                exportJSON: data,
                attachments: fetchAllAttachments()
            )
        } else {
            // Just save JSON/CSV
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dequeue_export_\(Date().iso8601).json")
            try data.write(to: tempURL)
            return tempURL
        }
    }
    
    private func createZIPArchive(
        exportJSON: Data,
        attachments: [Attachment]
    ) async throws -> URL {
        // Use ZIPFoundation or native compression
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dequeue_export_\(Date().iso8601).zip")
        
        let archive = try ZipArchive(url: zipURL, mode: .create)
        
        // Add export.json
        try archive.addEntry(with: "export.json", data: exportJSON)
        
        // Add all attachments
        for attachment in attachments {
            let fileData = try await downloadAttachment(attachment)
            try archive.addEntry(
                with: "attachments/\(attachment.filename)",
                data: fileData
            )
        }
        
        try archive.close()
        return zipURL
    }
}
```

**Background Task (iOS):**
```swift
// Register background task for large exports
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "app.dequeue.export",
    using: nil
) { task in
    task.expirationHandler = {
        // Cancel export if out of time
    }
    
    // Perform export
    Task {
        let url = try await DataExportService().exportAllData(...)
        // Notify user
        task.setTaskCompleted(success: true)
    }
}
```

### 2. Account & Data Deletion

#### What's Deleted

**Complete erasure:**
- ✅ All Stacks, Tasks, Reminders (local + backend)
- ✅ All Events in event history (backend)
- ✅ All Attachments (local + R2 storage)
- ✅ User account record (backend)
- ✅ Authentication tokens (Clerk session)
- ✅ All synced devices cleared

**NOT deleted:**
- ❌ Anonymized analytics (if opt-in enabled) - aggregate only, no PII
- ❌ Billing/payment history (required for accounting, per Stripe)

#### User Flow

**Settings → Privacy → Delete My Account**

1. User taps "Delete My Account"
2. Warning sheet appears:
   ```
   Delete Your Account?
   
   This will permanently delete:
   • All your Stacks and Tasks
   • All attachments and files
   • Your entire event history
   • Your account on all devices
   
   This action CANNOT be undone.
   
   Export your data first? [Export Now]
   
   To confirm, type: DELETE
   
   [Text field]
   
   [Cancel]  [Delete My Account]
   ```
3. User must type "DELETE" exactly (case-insensitive)
4. "Delete My Account" button enabled once typed correctly
5. User taps button → Confirmation dialog: "Are you absolutely sure?"
6. Deletion begins (background process)
7. Progress: "Deleting data... Please wait."
8. On completion:
   - All local data wiped
   - User signed out
   - App resets to fresh install state
   - Confirmation: "Your account has been deleted. All data erased."

**Optional: Export Before Delete**
- Prominent "Export Now" button before deletion
- If tapped, runs export flow, then returns to deletion screen
- Reduces regret ("I wish I'd saved my data first")

#### Technical Implementation

**Backend API:**
```http
DELETE /users/me
Authorization: Bearer {jwt}
```

**Backend logic:**
```go
func (s *UserService) DeleteAccount(ctx context.Context, userID string) error {
    // 1. Delete all events for this user
    if err := s.eventStore.DeleteAllForUser(ctx, userID); err != nil {
        return err
    }
    
    // 2. Delete all attachments from R2
    attachments, err := s.attachmentStore.ListForUser(ctx, userID)
    if err != nil {
        return err
    }
    for _, att := range attachments {
        if err := s.r2Client.Delete(ctx, att.Key); err != nil {
            log.Warn("Failed to delete attachment", "key", att.Key, "error", err)
            // Continue anyway - don't block account deletion
        }
    }
    
    // 3. Delete user record
    if err := s.userStore.Delete(ctx, userID); err != nil {
        return err
    }
    
    // 4. Revoke auth tokens (Clerk API)
    if err := s.clerkClient.DeleteUser(ctx, userID); err != nil {
        log.Error("Failed to delete Clerk user", "error", err)
        // Continue - user record is gone, tokens will expire
    }
    
    // 5. Trigger sync event to all devices: "account deleted"
    // Devices will wipe local data and sign out
    s.syncBus.Publish(ctx, AccountDeletedEvent{UserID: userID})
    
    return nil
}
```

**iOS deletion flow:**
```swift
func deleteAccount() async throws {
    // 1. Call backend API
    try await apiClient.deleteAccount()
    
    // 2. Wipe local data
    let modelContext = ModelContext(...)
    try await modelContext.deleteAll(Stack.self)
    try await modelContext.deleteAll(Task.self)
    try await modelContext.deleteAll(Reminder.self)
    try await modelContext.save()
    
    // 3. Delete local attachments
    try FileManager.default.removeItem(at: attachmentsDirectory)
    
    // 4. Clear all UserDefaults
    if let bundleID = Bundle.main.bundleIdentifier {
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
    }
    
    // 5. Clear keychain (auth tokens)
    try KeychainManager.deleteAll()
    
    // 6. Sign out
    try await ClerkSDK.shared.signOut()
    
    // 7. Reset app to fresh state
    // (App will restart and show onboarding)
}
```

**Grace Period (Optional):**
Instead of immediate deletion, queue for deletion in 30 days:
- Safer for accidental deletions
- GDPR allows reasonable delays
- User can cancel within 30 days

**Decision:** Implement immediate deletion for MVP. Grace period can be added in Phase 2 if needed.

### 3. Biometric App Lock

#### Behavior

**When enabled:**
- App requires Face ID / Touch ID on launch
- Configurable grace period: "Lock after X minutes in background"
- Fallback to device passcode if biometric fails
- Does NOT encrypt data at rest (relies on iOS device encryption)

**Options:**
| Setting | Description | Default |
|---------|-------------|---------|
| Lock on Launch | Require auth every time app opens | Off |
| Lock after 1 min | Require auth if app backgrounded >1 min | On (recommended) |
| Lock after 5 min | Require auth if app backgrounded >5 min | Off |
| Lock immediately | Require auth as soon as app backgrounds | Off |

**User Flow:**

1. User enables "Require Face ID" in Settings → Privacy
2. Prompt: "Dequeue would like to use Face ID"
3. User approves
4. From now on, when app launches (or returns from background > grace period):
   - Black screen with lock icon
   - "Unlock Dequeue" prompt
   - Face ID / Touch ID activates
   - On success: App UI appears
   - On failure: "Try Again" / "Use Passcode"

**Lock Screen:**
```swift
struct BiometricLockScreen: View {
    @State private var isUnlocking = false
    let onUnlock: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.primary)
            
            Text("Dequeue is Locked")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Use Face ID to unlock")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            if !isUnlocking {
                Button("Unlock") {
                    isUnlocking = true
                    authenticate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                ProgressView()
            }
        }
        .padding()
        .onAppear {
            authenticate()  // Auto-trigger on appear
        }
    }
    
    func authenticate() {
        let context = LAContext()
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock Dequeue"
        ) { success, error in
            DispatchQueue.main.async {
                if success {
                    onUnlock()
                } else {
                    isUnlocking = false
                    // Show error or fallback to passcode
                }
            }
        }
    }
}
```

#### Technical Implementation

**LocalAuthentication Framework:**
```swift
import LocalAuthentication

class BiometricLockManager {
    private let context = LAContext()
    
    func canUseBiometrics() -> Bool {
        var error: NSError?
        return context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
    }
    
    func authenticate() async throws {
        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock Dequeue to view your tasks"
            ) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? BiometricError.unknown)
                }
            }
        }
    }
}
```

**App State Management:**
```swift
@main
struct DequeueApp: App {
    @State private var isLocked = false
    @State private var lastBackgroundTime: Date?
    
    var body: some Scene {
        WindowGroup {
            if isLocked {
                BiometricLockScreen(onUnlock: {
                    isLocked = false
                })
            } else {
                MainTabView()
            }
        }
        .onChange(of: scenePhase) { old, new in
            switch new {
            case .background:
                lastBackgroundTime = Date()
            case .active:
                checkIfShouldLock()
            default:
                break
            }
        }
    }
    
    func checkIfShouldLock() {
        guard BiometricSettings.isEnabled else { return }
        
        let gracePeriod = BiometricSettings.gracePeriodMinutes * 60.0
        
        if let lastBackground = lastBackgroundTime,
           Date().timeIntervalSince(lastBackground) > gracePeriod {
            isLocked = true
        }
    }
}
```

**UserDefaults Settings:**
```swift
struct BiometricSettings {
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "biometricLockEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "biometricLockEnabled") }
    }
    
    static var gracePeriodMinutes: Double {
        get { UserDefaults.standard.double(forKey: "biometricGracePeriod") }
        set { UserDefaults.standard.set(newValue, forKey: "biometricGracePeriod") }
    }
}
```

**Important:** Biometric lock does NOT encrypt data at rest. It's a UI-level gate. Data is always accessible to the app process. This is standard for app locks and acceptable - iOS device encryption protects data at rest.

---

## Acceptance Criteria

### Data Export
- [ ] "Export My Data" in Settings → Privacy
- [ ] User can choose JSON or CSV format
- [ ] User can include/exclude Events and Attachments
- [ ] Export generates valid JSON/CSV
- [ ] Attachments included in ZIP with manifest
- [ ] Export completes for large datasets (1000+ Stacks, 10,000+ Tasks)
- [ ] Share sheet works (save to Files, AirDrop, email)
- [ ] Background processing for large exports (>100 MB)

### Account Deletion
- [ ] "Delete My Account" in Settings → Privacy
- [ ] Warning screen clearly explains what will be deleted
- [ ] User must type "DELETE" to confirm
- [ ] Optional "Export Now" before deletion
- [ ] Backend API deletes all user data (events, attachments, user record)
- [ ] Local data wiped completely
- [ ] User signed out
- [ ] App resets to fresh state
- [ ] No orphaned data left behind

### Biometric Lock
- [ ] "Require Face ID" toggle in Settings → Privacy
- [ ] Works with Face ID (iPhone X+, iPad Pro)
- [ ] Works with Touch ID (older devices)
- [ ] Configurable grace period (immediate, 1 min, 5 min)
- [ ] Fallback to device passcode if biometric fails
- [ ] Lock screen appears on app launch (if enabled)
- [ ] Lock screen appears after background > grace period
- [ ] Authentication quick and smooth (<1 sec)

### Design
- [ ] Privacy settings grouped logically in Settings
- [ ] Export progress indicator for large datasets
- [ ] Deletion warning is prominent and clear (no dark patterns)
- [ ] Biometric lock screen is branded and polished
- [ ] Error messages are helpful (e.g., "Face ID not available")

### Legal/Compliance
- [ ] Meets GDPR Article 20 (Right to Data Portability)
- [ ] Meets GDPR Article 17 (Right to Erasure)
- [ ] Privacy Policy updated to reflect data export/deletion
- [ ] Terms of Service mention data retention policies

---

## Edge Cases

1. **Export while offline**: Works (all data is local), attachments included
2. **Delete while offline**: Shows error: "Connect to internet to delete account"
3. **Export with no data**: Returns empty JSON/CSV (valid but empty)
4. **Export with >10 GB attachments**: Warn user, may take 10+ minutes
5. **Delete account with pending sync**: Sync canceled, deletion proceeds
6. **Biometric not available (old device)**: Hide biometric lock option, show message
7. **Biometric fails repeatedly**: Fallback to passcode after 3 attempts
8. **App locked, notification arrives**: Lock screen shown when user taps notification

---

## Testing Strategy

### Unit Tests
```swift
@Test func exportGeneratesValidJSON() async throws {
    let stack = Stack(title: "Test", ...)
    await modelContext.insert(stack)
    
    let exporter = DataExportService()
    let url = try await exporter.exportAllData(format: .json, ...)
    
    let data = try Data(contentsOf: url)
    let decoded = try JSONDecoder().decode(ExportData.self, from: data)
    
    #expect(decoded.stacks.count == 1)
    #expect(decoded.stacks[0].title == "Test")
}

@Test func deleteAccountWipesAllData() async throws {
    let stack = Stack(title: "Test", ...)
    await modelContext.insert(stack)
    
    try await AccountManager().deleteAccount()
    
    let remaining = try await modelContext.fetch(FetchDescriptor<Stack>())
    #expect(remaining.isEmpty)
}

@Test func biometricLockRequiresAuth() async throws {
    BiometricSettings.isEnabled = true
    
    let manager = BiometricLockManager()
    #expect(manager.isLocked == true)
    
    try await manager.authenticate()
    #expect(manager.isLocked == false)
}
```

### Integration Tests
- Export 1000 Stacks + 10,000 Tasks → Verify JSON valid
- Export with attachments → Verify ZIP structure
- Delete account → Verify backend deletes data
- Enable biometric lock → Verify lock screen appears on launch

### Manual Testing
- Test export on device with large dataset
- Test deletion flow (use test account!)
- Test biometric lock with Face ID and Touch ID devices
- Test error cases (network failure during delete, etc.)
- Verify GDPR compliance with legal team

---

## Implementation Plan

**Estimated: 3-4 days**

### Day 1: Data Export (6-8 hours)
1. Create `DataExportService` (2 hours)
2. Implement JSON serialization (2 hours)
3. Implement CSV export (1 hour)
4. Add attachment ZIP creation (1 hour)
5. Build Settings UI for export (1 hour)
6. Test on device with real data (1 hour)

### Day 2: Account Deletion (6-8 hours)
1. Create backend `/users/me DELETE` endpoint (2 hours)
2. Implement backend deletion logic (events, attachments, user) (2 hours)
3. Build iOS deletion flow (confirmation, API call, local wipe) (2 hours)
4. Test deletion end-to-end (1 hour)
5. Update Privacy Policy (1 hour)

### Day 3: Biometric Lock (4-6 hours)
1. Create `BiometricLockManager` (1 hour)
2. Build lock screen UI (1 hour)
3. Integrate with app lifecycle (lock/unlock logic) (2 hours)
4. Add Settings toggle and grace period options (1 hour)
5. Test on Face ID and Touch ID devices (1 hour)

### Day 4: Polish & Testing (4-6 hours)
1. Unit tests for all three features (2 hours)
2. Integration tests (1 hour)
3. Manual testing on devices (2 hours)
4. Documentation + Privacy Policy updates (1 hour)
5. PR review & merge (1 hour + CI time)

**Total: 20-28 hours** (spread across 4 days)

---

## Dependencies

- ✅ Backend API for account deletion (new endpoint)
- ✅ iOS LocalAuthentication framework (built-in)
- ✅ ZIPFoundation or native compression (for attachments ZIP)
- ⚠️ Legal review of Privacy Policy updates (before ship)

**Blockers:**
- Backend `/users/me DELETE` endpoint (need to implement)

---

## Out of Scope

- Grace period for account deletion (30-day undo) - Phase 2
- Export scheduling (weekly auto-export) - Phase 2
- Encrypted exports (password-protected ZIP) - Phase 2
- Biometric lock on specific Stacks (all-or-nothing for MVP)

---

## Success Metrics

**Adoption:**
- % of users who enable biometric lock
- % of users who export data at least once

**Compliance:**
- Zero GDPR complaints or data retention issues

**Trust:**
- User survey: "I trust Dequeue with my data" (target: 90%+ agree)

**Retention:**
- Users with biometric lock have higher retention (hypothesis)

---

**Next Steps:**
1. Review PRD with Victor and legal team
2. Create implementation tickets (DEQ-XXX)
3. Legal review Privacy Policy changes
4. Implement backend deletion endpoint first (blocker)
5. Implement iOS features when CI responsive
6. Ship and monitor adoption

**Privacy and user control are non-negotiable.** Let's get this right. 🔒
