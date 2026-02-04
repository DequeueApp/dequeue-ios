# Initial Sync Progress Tracking - PRD

**Epic:** DEQ-202 - Initial Sync Experience  
**Author:** Ada (Dequeue Engineer)  
**Date:** 2026-02-03  
**Status:** Draft

## Problem Statement

When a new device downloads its initial event history, users see a loading screen that shows "X events synced" but no indication of total progress. They don't know if they have 100 or 10,000 events to sync, leading to uncertainty about how long to wait.

**Current State:**
- ✅ `InitialSyncLoadingView` exists and hides UI flashing (DEQ-204, PR #236)
- ✅ Backend `/v1/sync/meta` endpoint returns total event count
- ❌ iOS never calls `/sync/meta` to get total count
- ❌ No progress bar showing percentage complete
- ❌ Users see "42 events synced" with no context of total

## Solution

Call `/sync/meta` when initial sync begins to fetch total event count, then display accurate progress with a determinate progress bar.

## Technical Design

### 1. Add API Client Method

**File:** `Dequeue/API/APIClient.swift`

```swift
struct SyncMetaResponse: Codable {
    let eventCount: Int
    let lastEventTs: Int64?
    let lastEventId: String?
    let lastSyncedAtTs: Int64?
}

extension APIClient {
    func getSyncMeta() async throws -> SyncMetaResponse {
        let url = baseURL.appendingPathComponent("/v1/sync/meta")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(SyncMetaResponse.self, from: data)
    }
}
```

### 2. Update SyncManager

**File:** `Dequeue/Sync/SyncManager.swift`

Add method to fetch and store total event count:

```swift
actor SyncManager {
    // ... existing properties ...
    
    /// Fetch total event count from backend for progress tracking
    func fetchInitialSyncTotal() async throws {
        guard let apiClient = self.apiClient else {
            throw SyncError.notConnected
        }
        
        let meta = try await apiClient.getSyncMeta()
        _initialSyncTotalEvents = meta.eventCount
        
        log.info("Initial sync total: \(meta.eventCount) events")
    }
    
    /// Begin initial sync process with progress tracking
    func startInitialSync() async {
        _isInitialSyncInProgress = true
        _initialSyncEventsProcessed = 0
        
        // Fetch total event count for progress bar
        do {
            try await fetchInitialSyncTotal()
        } catch {
            log.error("Failed to fetch sync meta: \(error.localizedDescription)")
            // Continue without total - will show indeterminate progress
        }
        
        // Begin pulling events...
    }
}
```

### 3. Update InitialSyncLoadingView

**File:** `Dequeue/Views/Sync/InitialSyncLoadingView.swift`

```swift
struct InitialSyncLoadingView: View {
    let eventsProcessed: Int
    let totalEvents: Int?  // nil = unknown total
    
    var progress: Double? {
        guard let total = totalEvents, total > 0 else { return nil }
        return Double(eventsProcessed) / Double(total)
    }
    
    var body: some View {
        VStack(spacing: Constants.verticalSpacing) {
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .font(.system(size: Constants.iconSize))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    .linear(duration: Constants.animationDuration)
                    .repeatForever(autoreverses: false),
                    value: isAnimating
                )

            Text("Syncing Your Data")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Setting up your account on this device...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Progress bar if we know the total
            if let progress = progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                
                Text("\(eventsProcessed) of \(totalEvents!) events")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            } else if eventsProcessed > 0 {
                // Indeterminate if total unknown
                ProgressView()
                
                Text("\(eventsProcessed) events synced")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding()
        .onAppear {
            isAnimating = true
        }
    }
}
```

### 4. Update DequeueApp Integration

**File:** `Dequeue/DequeueApp.swift`

Pass total events to the loading view:

```swift
if syncStatusViewModel.isInitialSyncInProgress {
    InitialSyncLoadingView(
        eventsProcessed: await syncManager.initialSyncEventsProcessed,
        totalEvents: await syncManager.initialSyncTotalEvents > 0 
            ? await syncManager.initialSyncTotalEvents 
            : nil
    )
} else {
    // Main content
}
```

## User Experience

**Before:**
```
🔄 Syncing Your Data
Setting up your account on this device...
42 events synced
```
User thinks: "Is that good? How many more?"

**After:**
```
🔄 Syncing Your Data
Setting up your account on this device...
[=====>          ] 42%
42 of 100 events
```
User thinks: "Nice, almost halfway done!"

## Acceptance Criteria

- [ ] iOS calls `/v1/sync/meta` when initial sync begins
- [ ] Total event count stored in `SyncManager._initialSyncTotalEvents`
- [ ] `InitialSyncLoadingView` displays determinate progress bar when total is known
- [ ] Falls back to indeterminate progress if `/sync/meta` call fails
- [ ] Progress updates smoothly as events are processed
- [ ] Unit tests verify progress calculation
- [ ] Unit tests verify graceful degradation when total is unknown

## Edge Cases

1. **Slow `/sync/meta` response:** Show indeterminate progress until meta arrives
2. **Auth token expired:** Refresh token and retry `/sync/meta` call
3. **Network error:** Continue with indeterminate progress, don't block sync
4. **Zero events:** Show "Account is ready" immediately
5. **Meta returns incorrect count:** Progress may exceed 100% (clamp to 100% in UI)

## Future Enhancements

**Phase 3 (Future):** WebSocket streaming for faster initial sync (DEQ-206, DEQ-207)
- Instead of REST polling, stream all events via WebSocket
- Reduce round-trip latency for large event histories
- Server pushes events continuously, client displays progress
- Much faster than request-response cycle

## Testing Strategy

### Unit Tests
```swift
@Test func initialSyncProgressCalculation() async throws {
    let manager = SyncManager(...)
    await manager.setInitialSyncTotal(100)
    await manager.setInitialSyncProcessed(42)
    
    let progress = await manager.initialSyncProgress
    #expect(progress == 0.42)
}

@Test func initialSyncProgressUnknownTotal() async throws {
    let manager = SyncManager(...)
    // Don't set total
    await manager.setInitialSyncProcessed(42)
    
    let progress = await manager.initialSyncProgress
    #expect(progress == nil)
}
```

### Integration Tests
- Mock `/sync/meta` to return known total
- Trigger initial sync
- Verify progress bar appears and updates correctly
- Verify events synced matches `/sync/meta` count

## Implementation Plan

1. **Add API method** (30 min) - Low risk, straightforward HTTP call
2. **Update SyncManager** (1 hour) - Fetch meta on initial sync start
3. **Update InitialSyncLoadingView** (1 hour) - Conditional progress bar
4. **Unit tests** (1 hour) - Progress calculation tests
5. **Integration test** (30 min) - End-to-end sync flow
6. **PR review & merge** (15 min + CI time)

**Total Estimate:** ~4 hours of dev work

## Dependencies

- ✅ Backend `/v1/sync/meta` endpoint (already shipped)
- ✅ `InitialSyncLoadingView` exists (PR #236)
- ✅ `SyncManager` tracks initial sync state

No blockers - ready to implement!

## Out of Scope

- WebSocket streaming (separate epic: DEQ-206, DEQ-207)
- Real-time event count updates during sync (meta is fetched once at start)
- Pause/resume sync controls
- "Skip sync" option (security/data integrity concern)

---

**Next Steps:**
1. Review this PRD with Victor
2. Create implementation ticket (DEQ-XXX)
3. Implement when CI is responsive
4. Ship and monitor adoption

This completes the "user-visible progress" part of DEQ-202. WebSocket streaming (Phase 3) is a separate effort for performance optimization.
