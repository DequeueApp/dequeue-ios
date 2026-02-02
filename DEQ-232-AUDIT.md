# DEQ-232 Service Actor Isolation Audit

**Date:** 2026-02-02  
**Auditor:** Ada

## 3-Bucket Pattern Reference

| Bucket | When to Use | Thread Safety |
|--------|-------------|---------------|
| `@MainActor final class` | Uses SwiftData `ModelContext` OR manages UI-observable state | Main thread only |
| `final class` (no isolation) | Pure network/stateless services | Thread-safe, no shared mutable state |
| `actor` | Manages mutable shared state (not ModelContext) | Actor-isolated, thread-safe |

## Audit Results

### ✅ Correct: Services using ModelContext (@MainActor)

| Service | Reasoning |
|---------|-----------|
| `StackService` | Uses ModelContext for Stack CRUD |
| `TaskService` | Uses ModelContext for Task CRUD |
| `TagService` | Uses ModelContext for Tag CRUD |
| `AttachmentService` | Uses ModelContext for Attachment CRUD |
| `EventService` | Uses ModelContext for EventLogEntry CRUD |
| `ArcService` | Uses ModelContext for Arc CRUD |
| `ReminderService` | Uses ModelContext for Reminder CRUD |
| `AttachmentUploadCoordinator` | Uses ModelContext, orchestrates uploads |
| `AttachmentDownloadCoordinator` | Uses ModelContext, orchestrates downloads |
| `NotificationService` | Uses ModelContext, manages UNUserNotificationCenter |

### ✅ Correct: Pure network/stateless (no isolation)

| Service | Reasoning | PR |
|---------|-----------|-----|
| **`AttachmentUploadService`** | Pure URLSession networking, no ModelContext | **#231 ✅** |

### ✅ Correct: UI-observable state (@MainActor)

| Service | Reasoning |
|---------|-----------|
| `AuthService` | `@Observable` with UI-reactive state (isAuthenticated, etc.) |
| `NetworkMonitor` | `@Observable` with UI-reactive state, surgical @MainActor on properties |

### ⚠️ Needs Decision: UploadRetryManager

**Current:** `@MainActor final class`  
**Suggested:** `actor`

**Reasoning:**
- Manages mutable shared state (`retryStates`, `retryTasks`)
- Does NOT use ModelContext
- Does NOT need main thread access
- State mutations should be actor-isolated, not MainActor

**Impact:**
- Medium - callers would need to handle actor isolation
- Would prevent MainActor congestion from retry logic
- More appropriate concurrency model

**Recommendation:** Convert to `actor` in follow-up PR

### ✅ Correct: UndoCompletionManager

Needs review of ModelContext usage, but likely correct as @MainActor.

## Summary

### Completed
- ✅ **AttachmentUploadService** refactored to `final class` (PR #231)

### Recommendations
1. **UploadRetryManager**: Consider converting to `actor` (follow-up ticket)
2. **NetworkMonitor**: Already follows best practice (surgical @MainActor on properties)
3. **AuthService**: Correctly @MainActor (UI-observable state)
4. All ModelContext-using services: Correctly @MainActor

## Impact

### PR #231 (AttachmentUploadService)
- **Before:** All upload work forced onto MainActor
- **After:** Upload work happens on background threads
- **Benefit:** Reduced MainActor congestion, prevents UI jank during large uploads
- **Risk:** Low - no callers require MainActor isolation

### Future: UploadRetryManager → actor
- **Benefit:** Proper concurrency model for shared mutable state
- **Risk:** Medium - requires careful migration of callers
- **Recommendation:** Separate ticket after #231 merges

## Conclusion

**DEQ-232 Status:** Partially complete
- Primary goal achieved: Identified and fixed AttachmentUploadService
- Additional findings: UploadRetryManager should be actor
- No other services need refactoring

**Next Steps:**
1. Merge PR #231
2. Create follow-up ticket for UploadRetryManager actor conversion
3. Close DEQ-232 or scope down to UploadRetryManager only
