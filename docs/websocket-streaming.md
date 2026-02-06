# WebSocket Streaming for Fast Initial Sync

**Implemented:** DEQ-243 (PR #247)  
**Backend:** DEQ-242 (PR #42 - merged)  
**Status:** Implementation complete, CI pending

## Problem

Initial sync using REST API polling was slow for large event histories:
- 10,000 events = 30-60 seconds
- Multiple HTTP requests (one per batch of 100)
- No progress indication during multi-batch sync
- Poor user experience on first login

## Solution

WebSocket streaming provides 5-10x performance improvement:
- Single persistent connection
- Server streams all events in batches
- Real-time progress updates
- Automatic fallback to REST on any error

## Architecture

### Message Types

#### Client → Server

**sync.stream.request**
```json
{
  "type": "sync.stream.request",
  "since": "2026-02-05T15:30:00Z"  // Last checkpoint (RFC3339)
}
```

#### Server → Client

**sync.stream.start**
```json
{
  "type": "sync.stream.start",
  "totalEvents": 10543  // Total events to stream
}
```

**sync.stream.batch**
```json
{
  "type": "sync.stream.batch",
  "events": [ /* array of event objects */ ],
  "batchIndex": 0,
  "isLast": false
}
```

**sync.stream.complete**
```json
{
  "type": "sync.stream.complete",
  "processedEvents": 10543,
  "newCheckpoint": "2026-02-05T22:15:30Z"
}
```

**sync.stream.error**
```json
{
  "type": "sync.stream.error",
  "error": "Database connection failed",
  "code": "DB_ERROR"
}
```

### Flow Diagram

```
Client                                Server
  |                                      |
  |--- Connect WebSocket /v1/sync/stream--->|
  |                                      |
  |--- sync.stream.request (since=...) -->|
  |                                      |
  |<-- sync.stream.start (totalEvents)---|
  |    (Set progress: 0 / 10543)         |
  |                                      |
  |<-- sync.stream.batch (events 0-999)--|
  |    (Process events, update progress) |
  |                                      |
  |<-- sync.stream.batch (events 1000-1999)--|
  |    (Process events, update progress) |
  |                                      |
  |<-- ... more batches ...              |
  |                                      |
  |<-- sync.stream.batch (isLast=true)--|
  |    (Process final batch)             |
  |                                      |
  |<-- sync.stream.complete              |
  |    (Save new checkpoint)             |
  |                                      |
  |--- Close WebSocket                   |
```

## Implementation

### SyncManager.streamEventsViaWebSocket()

Private method that handles the entire WebSocket flow:

1. **Connect**
   - Build WebSocket URL from API base URL (http/https → ws/wss)
   - Add Authorization header with Bearer token
   - Create `URLSessionWebSocketTask` and resume

2. **Send Request**
   - Encode `SyncStreamRequest` with last checkpoint
   - Send via WebSocket as binary data (JSON)

3. **Receive Loop**
   - Loop until `sync.stream.complete` received
   - Parse each message by type
   - Handle start, batch, complete, error

4. **Process Events**
   - Reuse existing `processIncomingEvents()` logic
   - Filter duplicates and invalid events (unchanged from REST flow)
   - Update progress state (`_initialSyncEventsProcessed`, `_initialSyncTotalEvents`)

5. **Save Checkpoint**
   - On completion, save new checkpoint
   - Return true (success)

6. **Error Handling**
   - On any error, log and return false
   - Caller falls back to REST

### SyncManager.pullEvents() - Updated

```swift
func pullEvents() async throws {
    // Try WebSocket streaming first (DEQ-243)
    do {
        let success = try await streamEventsViaWebSocket()
        if success {
            os_log("[Sync] Pull completed via WebSocket streaming")
            return
        } else {
            os_log("[Sync] WebSocket returned false, falling back to REST")
        }
    } catch {
        os_log("[Sync] WebSocket failed, falling back to REST: \(error)")
    }
    
    // Fallback: REST API polling (existing code unchanged)
    // ...
}
```

### Progress Tracking

Progress state is shared between WebSocket and REST flows:

```swift
// Internal state (accessed via @Published properties)
private var _isInitialSyncInProgress: Bool = false
private var _initialSyncTotalEvents: Int = 0
private var _initialSyncEventsProcessed: Int = 0

// Published properties (SwiftUI binding)
@Published var isInitialSyncInProgress: Bool = false
@Published var initialSyncProgress: (processed: Int, total: Int)?
```

**When WebSocket streams:**
- `sync.stream.start` sets `_initialSyncTotalEvents`
- Each batch increments `_initialSyncEventsProcessed`
- UI reactively updates progress bar

## UI Integration

### InitialSyncLoadingView

Shows progress during sync:

```swift
if viewModel.isInitialSyncInProgress,
   let progress = viewModel.initialSyncProgress {
    ProgressView(value: Double(progress.processed),
                 total: Double(progress.total))
    
    Text("\(progress.processed) of \(progress.total) events")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

## Fallback Strategy

WebSocket streaming is **optional**. If it fails for any reason, sync continues via REST:

**Failure Scenarios:**
- WebSocket connection fails (network, firewall, proxy)
- Backend doesn't support `/v1/sync/stream`
- Message format mismatch
- Connection drops mid-stream

**Fallback Behavior:**
- `streamEventsViaWebSocket()` returns `false`
- `pullEvents()` immediately tries REST polling
- REST polling logic is unchanged (proven reliable)
- No user-visible error (transparent fallback)

## Performance

### Benchmarks (Expected)

| Events | REST (polling) | WebSocket | Improvement |
|--------|----------------|-----------|-------------|
| 1,000  | 5-8 sec        | 1-2 sec   | 4-5x faster |
| 10,000 | 30-60 sec      | 5-10 sec  | 5-10x faster |
| 50,000 | 3-5 min        | 30-60 sec | 5-6x faster |

**Why faster?**
- Single connection vs many HTTP requests
- No per-request overhead (headers, TLS handshake, etc.)
- Server can stream continuously without waiting for client polls
- Binary protocol (efficient encoding)

### Real-World Performance (TBD)

*Actual measurements pending production deployment.*

## Testing

### Unit Tests

Location: `DequeueTests/SyncManager+WebSocketTests.swift`

**Coverage:**
- Message serialization/deserialization
- Progress state updates
- Event processing integration
- Checkpoint saving
- Fallback behavior

### Manual Testing

**Scenarios:**
1. ✅ Fresh device sync (10k+ events)
2. ✅ Incremental sync (few new events)
3. ✅ Disconnect mid-stream (should fallback)
4. ✅ Backend unavailable (should fallback)
5. ⏳ Large sync (50k+ events) - pending production test

## Backend

Backend implementation: `dequeue-api` PR #42 (merged)

**Endpoint:** `GET /v1/sync/stream` (WebSocket upgrade)

**Documentation:** See `dequeue-api/docs/websocket-streaming.md`

## Future Enhancements

### Compression
- Gzip compress event batches before sending
- Reduces bandwidth 5-10x for large syncs
- Trade-off: slight CPU overhead

### Delta Sync
- Send only changed fields, not full events
- Reduces payload size for large events
- Requires event versioning and diffing

### Prioritization
- Send critical events first (active Stack/Task)
- Rest of events stream in background
- Enables faster "time to interactive"

### Resumable Streams
- Save progress mid-stream
- Resume from last batch on disconnect
- Avoids re-downloading already processed events

## References

- Backend PR: dequeue-api #42 (DEQ-242)
- iOS PR: dequeue-ios #247 (DEQ-243)
- Planning doc: `DEQ-243-PLAN.md`
- Progress UI: `DequeueTests/SyncManager+ProgressTests.swift`

---

*Last updated: 2026-02-05*
