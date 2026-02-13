# DEQ-243: iOS WebSocket Stream Consumer

**Status:** ✅ IMPLEMENTED  
**Documentation:** docs/websocket-streaming.md  
**Related:** DEQ-240 (sync progress UI, PR #254)  
**Note:** PR #247 closed, but feature implemented in SyncManager  
**Completed:** February 2026

## Goal
Implement WebSocket streaming for fast initial sync with real-time progress.

## Current State (REST Polling)
- `SyncManager.pullEvents()` uses REST API `/sync/pull`
- Fetches in batches of 100 (hardcoded `pullBatchSize`)
- Multiple HTTP requests (one per batch)
- No progress indication during multi-batch sync
- Takes 30-60s for 10k events

## Target State (WebSocket Streaming)
- New `SyncManager.streamEventsViaWebSocket()` method
- Single persistent WebSocket connection to `/v1/sync/stream`
- Receives total count + batch progress
- Falls back to REST if WebSocket unavailable  
- Target: 5-10s for 10k events (5-10x faster)

## Implementation Plan

### 1. Add WebSocket Message Types
Location: `Dequeue/Sync/SyncManager.swift`

```swift
// MARK: - WebSocket Stream Messages (DEQ-243)

private struct SyncStreamRequest: Codable {
    let type: String // "sync.stream.request"
    let since: String? // RFC3339 timestamp
}

private struct SyncStreamStart: Codable {
    let type: String // "sync.stream.start"
    let totalEvents: Int64
}

private struct SyncStreamBatch: Codable {
    let type: String // "sync.stream.batch"
    let events: [[String: Any]] // Raw event objects
    let batchIndex: Int
    let isLast: Bool
}

private struct SyncStreamComplete: Codable {
    let type: String // "sync.stream.complete"
    let processedEvents: Int64
    let newCheckpoint: String
}

private struct SyncStreamError: Codable {
    let type: String // "sync.stream.error"
    let error: String
    let code: String?
}
```

### 2. Add Progress Callback Support
Update `SyncManager` to support progress reporting:

```swift
// Progress callback for UI updates
typealias SyncProgressCallback = (Int64, Int64) -> Void // (processed, total)

private var progressCallback: SyncProgressCallback?

func setSyncProgressCallback(_ callback: @escaping SyncProgressCallback) {
    self.progressCallback = callback
}
```

### 3. Implement WebSocket Streaming
New method in `SyncManager`:

```swift
private func streamEventsViaWebSocket() async throws -> Bool {
    // 1. Connect to /v1/sync/stream endpoint
    // 2. Send sync.stream.request with last checkpoint
    // 3. Receive sync.stream.start (set total count for progress)
    // 4. Loop: receive sync.stream.batch messages
    //    - Process events via existing processPullResponse logic
    //    - Call progressCallback with (processed, total)
    // 5. Receive sync.stream.complete
    // 6. Save new checkpoint
    // 7. Return true on success
    // On any error: log and return false (caller falls back to REST)
}
```

### 4. Update pullEvents to Try WebSocket First
Modify existing `pullEvents()`:

```swift
func pullEvents() async throws {
    // Try WebSocket streaming first
    do {
        let success = try await streamEventsViaWebSocket()
        if success {
            os_log("[Sync] WebSocket stream completed successfully")
            return
        }
    } catch {
        os_log("[Sync] WebSocket stream failed, falling back to REST: \(error)")
    }
    
    // Fallback to existing REST polling logic
    // ... (existing REST code unchanged)
}
```

### 5. Wire Up Progress to UI
Update `SyncStatusViewModel` to expose progress:

```swift
@Published var syncProgress: (processed: Int64, total: Int64)?

func setupProgressTracking() {
    syncManager.setSyncProgressCallback { [weak self] processed, total in
        Task { @MainActor in
            self?.syncProgress = (processed, total)
        }
    }
}
```

### 6. Update InitialSyncLoadingView
Add progress bar to loading view:

```swift
if let progress = viewModel.syncProgress {
    ProgressView(value: Double(progress.processed), 
                 total: Double(progress.total))
    Text("\(progress.processed) of \(progress.total) events")
        .font(.caption)
}
```

## Testing Strategy

### Unit Tests
- Message serialization/deserialization
- Progress callback invocation
- Error handling and fallback logic

### Integration Tests
- Mock WebSocket server responding with test data
- Verify 250 events stream correctly
- Verify fallback to REST on WebSocket error

### Manual Testing
- Test with real backend (staging)
- Verify progress bar updates smoothly
- Test disconnect/reconnect during stream
- Verify fallback works

## Success Criteria
- [x] Client sends sync.stream.request via WebSocket
- [x] Receives and processes all message types
- [x] Progress bar shows accurate X of Y
- [x] Falls back to REST if WebSocket unavailable
- [x] Handles disconnect during stream
- [x] 5-10x faster than REST (measure with 10k events)
- [x] Unit tests pass
- [x] No regressions in REST fallback

## Dependencies
- ✅ DEQ-242 (Backend WebSocket streaming) - COMPLETE
- Backend endpoint deployed at `/v1/sync/stream`
- Documented API in `dequeue-api/docs/websocket-streaming.md`

## Timeline Estimate
- Message types & structures: 30 min
- WebSocket streaming implementation: 2 hours
- Progress callback & UI integration: 1 hour
- Testing & refinement: 1 hour
- **Total: ~4 hours**

## Risks & Mitigations
- **Risk**: WebSocket connection unstable in production
  - **Mitigation**: Robust fallback to REST (existing code)
  
- **Risk**: Message format mismatch with backend
  - **Mitigation**: Backend API documented & validated in DEQ-242

- **Risk**: Progress updates janky/laggy
  - **Mitigation**: Throttle progress callbacks (max 10/sec)

## Notes
- Keep existing REST code unchanged (fallback path)
- WebSocket should be OPTIONAL enhancement, not breaking change
- Log performance metrics for comparison with REST
